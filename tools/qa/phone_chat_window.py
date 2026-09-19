#!/usr/bin/env python3
"""Bounded phone acceptance session. Requires the prepared APK kit and unlocked phone.

Updates Wing Dev in place; never uninstalls. Captures no chat text. Restores
refresh-rate settings and the normal candidate APK even after a test failure.
"""
import argparse
import hashlib
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from wing_perf_client import WingPerfClient

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True, help='Wireless ADB address:port')
parser.add_argument('--kit', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
manifest = json.loads((args.kit / 'manifest.json').read_text())
for artifact in manifest['artifacts']:
    file = args.kit / artifact['file']
    if hashlib.sha256(file.read_bytes()).hexdigest() != artifact['sha256']:
        raise SystemExit('Prepared APK checksum mismatch')
adb = ['adb', '-s', args.serial]
started = time.monotonic()
# Reserve the final four minutes for restoration, result inspection and reporting.
work_deadline = started + 16 * 60
saved_settings = {}
modified_app = False
report = {'source': manifest['candidateSource'], 'phases': {}}


def save():
    report['elapsedSeconds'] = round(time.monotonic() - started, 1)
    (args.output / 'session.json').write_text(json.dumps(report, indent=2) + '\n')


def call(*words, timeout=30):
    return subprocess.check_output(adb + list(words), text=True, timeout=timeout)


def phase(name, command, maximum):
    remaining = work_deadline - time.monotonic()
    if remaining < maximum:
        raise RuntimeError('Switching to cleanup before the 20-minute deadline')
    print(f"[{time.monotonic() - started:.0f}s] {name}", flush=True)
    with (args.output / (name + '.log')).open('w') as log:
        done = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                              timeout=maximum)
    report['phases'][name] = {'exitCode': done.returncode}
    save()
    if done.returncode:
        raise RuntimeError(name + ' failed; see saved phase log')


def install(file):
    global modified_app
    call('shell', 'am', 'force-stop', 'com.tarkilhk.wing.dev')
    modified_app = True
    call('install', '-r', '--user', '0', str(args.kit / file), timeout=90)


def launch_ready(label):
    begin = time.monotonic()
    call('shell', 'am', 'start', '-n', 'com.tarkilhk.wing.dev/com.tarkilhk.wing.MainActivity')
    stable = 0
    last = None
    while time.monotonic() - begin < 60:
        try:
            with WingPerfClient(args.serial) as client:
                last = client.action('snapshot')
            stable = stable + 1 if last['initialized'] and not last['loading'] else 0
            if stable >= 2:
                report[label] = {**last, 'confirmedReadyMs': round((time.monotonic() - begin) * 1000)}
                save()
                return
        except (RuntimeError, subprocess.SubprocessError, IndexError):
            pass
        time.sleep(1)
    raise RuntimeError('Chats did not reach a measurable state within 60 seconds')


def stop_for_cleanup(*_):
    raise TimeoutError('16-minute test cutoff reached; restoring the phone')


signal.signal(signal.SIGALRM, stop_for_cleanup)
signal.alarm(16 * 60)
try:
    connection = subprocess.check_output(['adb', 'connect', args.serial], text=True, timeout=15)
    if call('get-state').strip() != 'device':
        raise RuntimeError('Phone is not authorized for ADB')
    installed = call('shell', 'dumpsys', 'package', 'com.tarkilhk.wing.dev')
    match = re.search(r'versionCode=(\d+)', installed)
    if not match or int(match[1]) > manifest['baselineVersion']:
        raise RuntimeError('Installed Wing Dev version needs a newly numbered kit; no downgrade attempted')
    report['device'] = {
        'model': call('shell', 'getprop', 'ro.product.model').strip(),
        'android': call('shell', 'getprop', 'ro.build.version.release').strip(),
        'resolution': call('shell', 'wm', 'size').strip(),
        'density': call('shell', 'wm', 'density').strip(),
    }
    (args.output / 'display-before.txt').write_text(call('shell', 'dumpsys', 'display'))
    (args.output / 'battery-before.txt').write_text(call('shell', 'dumpsys', 'battery'))
    for name in ['peak_refresh_rate', 'min_refresh_rate']:
        saved_settings[name] = call('shell', 'settings', 'get', 'system', name).strip()
        call('shell', 'settings', 'put', 'system', name, '60.0')
    report['originalDisplaySettings'] = saved_settings.copy()
    save()
    install('baseline-22670.apk')
    launch_ready('baselineReady')
    (args.output / 'display-during.txt').write_text(call('shell', 'dumpsys', 'display'))
    phase('baseline', [sys.executable, 'tools/qa/measure_chat_scrolling.py', '--serial', args.serial,
                      '--label', manifest['baselineSource'], '--output', str(args.output / 'baseline.json')], 180)
    call('shell', 'am', 'force-stop', 'com.tarkilhk.wing.dev')
    quiet_started = time.monotonic()
    install('candidate-22671.apk')
    # The old baseline can exhaust Hermes' 60-second password-login window.
    # Let its attempts expire before evaluating the fixed client's sign-in.
    while time.monotonic() - quiet_started < 62:
        time.sleep(1)
    launch_ready('candidateReady')
    phase('candidate', [sys.executable, 'tools/qa/measure_chat_scrolling.py', '--serial', args.serial,
                       '--label', manifest['candidateSource'], '--output', str(args.output / 'candidate.json')], 180)
    phase('refreshes', [sys.executable, 'tools/qa/check_chat_refreshes.py', '--serial', args.serial,
                       '--output', str(args.output / 'refreshes.json')], 300)
    (args.output / 'memory-after.txt').write_text(call('shell', 'dumpsys', 'meminfo', 'com.tarkilhk.wing.dev'))
    (args.output / 'battery-after.txt').write_text(call('shell', 'dumpsys', 'battery'))
    candidate = json.loads((args.output / 'candidate.json').read_text())
    report['frameBudgetPassed'] = all(
        run[thread]['p95_ms'] <= 16 and run[thread]['p99_ms'] <= 32
        for run in candidate['runs'] for thread in ['build', 'raster'])
except Exception as error:
    report['failure'] = str(error)
    print('Session stopped: ' + str(error), flush=True)
finally:
    signal.alarm(0)
    # Restoration has its own reserved time and runs even if acceptance failed.
    if modified_app:
        try:
            install('normal-22672.apk')
            call('shell', 'am', 'start', '-n', 'com.tarkilhk.wing.dev/com.tarkilhk.wing.MainActivity')
            report['normalBuildRestored'] = True
        except Exception:
            report['normalBuildRestored'] = False
    for name, value in saved_settings.items():
        try:
            if value == 'null':
                call('shell', 'settings', 'delete', 'system', name)
            else:
                call('shell', 'settings', 'put', 'system', name, value)
        except Exception:
            report.setdefault('displayRestoreFailures', []).append(name)
    save()
print(json.dumps(report, indent=2))
if ('failure' in report or not report.get('frameBudgetPassed')
        or not report.get('normalBuildRestored') or report.get('displayRestoreFailures')):
    raise SystemExit(1)
