#!/usr/bin/env python3
"""Verify offline diagnostic ZIP sharing and process-restart retention on an owned emulator."""
import argparse
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.qa import run_notification_gate as android
from tools.qa.check_external_share import Device, HELPER, build_helper
from scripts.test import fingerprint
from scripts.test_vanilla_hermes import cleanup_signals

PACKAGE = 'com.tarkilhk.wing.dev'


def run(output):
    output.mkdir(parents=True, exist_ok=True)
    before = fingerprint()
    with (output / 'build.log').open('w') as log:
        subprocess.run(['flutter', 'build', 'apk', '--debug', '--no-pub',
                        '--target', 'integration_test/diagnostic_export_device.dart'],
                       cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    helper = build_helper(Path(os.environ['ANDROID_HOME']), Path(os.environ['JAVA_HOME']), output / 'helper')
    android.OUTPUT = output
    with android.owned_emulator() as serial:
        android.require_emulator(serial)
        device = Device(serial)
        device.adb('install', '-r', str(ROOT / 'build/app/outputs/flutter-apk/app-debug.apk'))
        device.adb('install', str(helper))

        def nodes():
            raw = device.shell('uiautomator', 'dump', '/sdcard/diagnostics-ui.xml')
            if 'dumped to:' not in raw:
                return []
            xml = device.shell('cat', '/sdcard/diagnostics-ui.xml')
            (output / 'latest-ui.xml').write_text(xml)
            return list(ET.fromstring(xml).iter('node'))

        def tap_label(label):
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                found = next((n for n in nodes() if label in (n.get('content-desc', '') + n.get('text', ''))
                              and n.get('enabled') == 'true'), None)
                if found is not None:
                    x1, y1, x2, y2 = map(int, re.findall(r'\d+', found.get('bounds')))
                    if x2 > x1 and y2 > y1:
                        device.shell('input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
                        return
                # Scroll the current surface, including an expanded Android chooser.
                device.shell('input', 'swipe', '500', '1500', '500', '400', '350')
            raise RuntimeError('Control unavailable: ' + label)

        def wait(check, label):
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if check(): return
                time.sleep(0.2)
            raise RuntimeError(label)

        for attempt in (1, 2):
            device.shell('am', 'start', '-n', PACKAGE + '/com.tarkilhk.wing.MainActivity')
            tap_label('Share diagnostic logs')
            (output / f'chooser-{attempt}.png').write_bytes(device.adb('exec-out', 'screencap', '-p', binary=True))
            tap_label('Receive Wing diagnostics')
            wait(lambda: device.private_exists(HELPER, 'files/diagnostics.zip'), 'Receiver did not read the shared ZIP')
            raw = device.private_read(HELPER, 'files/diagnostics.zip')
            (output / f'bundle-{attempt}.zip').write_bytes(raw)
            with zipfile.ZipFile(io.BytesIO(raw)) as bundle:
                if set(bundle.namelist()) != {'README.txt', 'manifest.json', 'device.json', 'events.jsonl'}:
                    raise RuntimeError('Incomplete diagnostic bundle')
                manifest = json.loads(bundle.read('manifest.json'))
                snapshot = json.loads(bundle.read('device.json'))
                events = [json.loads(line) for line in bundle.read('events.jsonl').splitlines()]
                if manifest['unavailable_sections']:
                    raise RuntimeError('Snapshot collection failed: ' + str(manifest['unavailable_sections']))
                if snapshot['app']['package'] != PACKAGE or 'network' not in snapshot or 'process_exits' not in snapshot:
                    raise RuntimeError('Missing native diagnostic context')
                incidents = [e for e in events if e['event'] == 'qa.incident']
                if len({e['process'] for e in incidents}) != attempt:
                    raise RuntimeError('Pre-restart incident did not survive')
                contents = b'\n'.join(bundle.read(n) for n in bundle.namelist())
                if b'fixture-secret' in contents or b'diagnostic-secret-chat' in contents:
                    raise RuntimeError('Exception prose leaked into export')
            wait(lambda: not device.shell('run-as', PACKAGE, 'find', 'cache/diagnostic-exports', '-name', '*.zip').strip(),
                 'Original ZIP was not cleaned after chooser handoff')
            device.shell('run-as', HELPER, 'rm', 'files/diagnostics.zip')
            device.shell('am', 'force-stop', PACKAGE)
        device.adb('uninstall', HELPER)
    after = fingerprint()
    if before != after:
        raise RuntimeError('Source changed during native verification')
    (output / 'result.json').write_text(json.dumps({'passed': True, 'source': before,
        'completed': ['offline-settings-share', 'cross-uid-zip-read', 'process-restart-retention',
                      'native-diagnostic-snapshot', 'secret-exclusion', 'share-stage-cleanup']}, indent=2) + '\n')
    print('Diagnostic native checks passed; emulator retired.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/feature-verification/diagnostics-native')
    args = parser.parse_args()
    with cleanup_signals():
        run(args.output.resolve())
