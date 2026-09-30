#!/usr/bin/env python3
"""Run offline native voice acceptance on an already booted disposable phone AVD.

Requires Flutter/adb on PATH and com.tarkilhk.wing.dev already installed. Resets
only that package's RECORD_AUDIO grant/user flags, then drives Android's actual
deny/grant dialogs and Home cancellation. Runs Flutter suites sequentially with
--no-uninstall --no-pub. Does not contact Hermes or invoke a speech provider.
Screens, native UI trees, Flutter logs and acceptance.json go under --output.
The disposable AVD retains microphone permission granted after a successful run.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
PACKAGE = 'com.tarkilhk.wing.dev'
PERMISSION = 'android.permission.RECORD_AUDIO'
PERMISSION_STEPS = {
    'VOICE_DENY_READY', 'VOICE_GRANT_READY', 'VOICE_BACKGROUND_READY',
    'VOICE_BACKGROUND_CANCELLED',
}


class Driver:
    def __init__(self, serial, output, timeout):
        self.serial = serial
        self.output = output
        self.timeout = timeout
        self.deadline = None
        self.process = None
        self.dump_path = '/sdcard/wing-voice-qa-' + uuid.uuid4().hex + '.xml'
        self.evidence = {
            'device': serial, 'package': PACKAGE, 'backend': 'none; offline fixtures',
            'status': 'running', 'suites': {}, 'native_actions': [],
            'limitations': [
                'Synthetic capture/playback does not establish transcription or speech quality.',
                'Local recognition quality, Hermes voice and live providers were not exercised.',
                'TTS start callbacks do not measure first audible speech or intelligibility.',
                'Physical phone acceptance remains separate.',
            ],
        }

    def remaining(self, maximum=25):
        if self.deadline is None:
            return maximum
        seconds = self.deadline - time.monotonic()
        if seconds <= 0:
            raise TimeoutError('Native voice suite exceeded its bounded timeout')
        return min(maximum, seconds)

    def adb(self, *command, binary=False):
        return subprocess.check_output(
            ['adb', '-s', self.serial, *command], text=not binary,
            stderr=subprocess.PIPE, timeout=self.remaining(),
        )

    def shell(self, *command):
        return self.adb('shell', shlex.join(command))

    def capture(self, label):
        (self.output / (label + '.png')).write_bytes(
            self.adb('exec-out', 'screencap', '-p', binary=True))

    def nodes(self, label):
        self.shell('uiautomator', 'dump', self.dump_path)
        raw = self.shell('cat', self.dump_path)
        (self.output / (label + '.xml')).write_text(raw)
        nodes = list(ET.fromstring(raw).iter('node'))
        if any(n.get('resource-id') in {'android:id/aerr_close', 'android:id/aerr_wait'}
               for n in nodes):
            self.capture(label + '-android-error')
            raise RuntimeError('Android reported a crash/ANR; inspect native captures')
        return nodes

    def granted(self):
        details = self.shell('dumpsys', 'package', PACKAGE)
        matches = re.findall(re.escape(PERMISSION) + r': granted=(true|false)', details)
        if len(matches) != 1:
            raise RuntimeError('Could not determine the dev app microphone permission')
        return matches[0] == 'true'

    def drive_permission(self, grant):
        label = 'microphone-grant' if grant else 'microphone-deny'
        button_id = ('permission_allow_foreground_only_button' if grant
                     else 'permission_deny_button')
        deadline = time.monotonic() + min(40, self.remaining(40))
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError('Flutter exited while waiting for ' + label)
            nodes = self.nodes(label)
            controller = [n for n in nodes
                          if n.get('package', '').endswith('.permissioncontroller')]
            if not any(re.search(r'microphone|record audio', n.get('text', '').lower())
                       for n in controller):
                time.sleep(.25)
                continue
            node = next((n for n in controller
                         if n.get('resource-id', '').split(':id/')[-1] == button_id
                         and n.get('enabled') == 'true'), None)
            if node is None:
                time.sleep(.25)
                continue
            bounds = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
            if bounds is None:
                raise RuntimeError('Permission button has no native tap bounds')
            left, top, right, bottom = map(int, bounds.groups())
            self.capture(label)
            self.shell('input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
            while time.monotonic() < deadline:
                if self.granted() == grant:
                    self.evidence['native_actions'].append({
                        'action': label, 'button': node.get('text'),
                        'resource_id': node.get('resource-id'), 'granted_after': grant,
                    })
                    return
                time.sleep(.2)
            break
        self.capture(label + '-failed')
        raise RuntimeError('Could not complete actual Android microphone dialog: ' + label)

    def permission_marker(self, marker):
        if marker == 'VOICE_DENY_READY':
            self.drive_permission(False)
        elif marker == 'VOICE_GRANT_READY':
            self.drive_permission(True)
        elif marker == 'VOICE_BACKGROUND_READY':
            self.nodes('capture-before-home')
            self.capture('capture-before-home')
            self.shell('input', 'keyevent', 'KEYCODE_HOME')
            time.sleep(.25)
            self.capture('capture-backgrounded')
            self.evidence['native_actions'].append({'action': 'Home during AAC capture'})
        elif marker == 'VOICE_BACKGROUND_CANCELLED':
            self.evidence['native_actions'].append({'action': 'Flutter verified foreground-loss cancellation'})
            component = self.shell('cmd', 'package', 'resolve-activity', '--brief',
                                   '-a', 'android.intent.action.MAIN',
                                   '-c', 'android.intent.category.LAUNCHER', PACKAGE).strip().splitlines()[-1]
            if not re.fullmatch(re.escape(PACKAGE) + r'/[\w.$]+', component):
                raise RuntimeError('Could not resolve the dev app launcher for resume')
            self.shell('am', 'start', '-W', '-n', component)
            self.capture('capture-cancelled-resumed')

    def stop_process(self):
        if self.process is None or self.process.poll() is not None:
            return
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            self.process.wait(timeout=10)
            return
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait(timeout=10)

    def run_suite(self, name, target, required_markers=None):
        command = ['flutter', 'test', target, '-d', self.serial, '--no-uninstall',
                   '--no-pub', '--reporter', 'expanded']
        log_path = self.output / (name + '-flutter.log')
        seen = set()
        transcript = ''
        started = time.monotonic()
        self.process = None
        self.deadline = time.monotonic() + self.timeout
        self.evidence['suites'][name] = {'command': command, 'log': log_path.name}
        try:
            with log_path.open('w') as log, log_path.open() as reader:
                self.process = subprocess.Popen(
                    command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                while True:
                    self.remaining()
                    exited = self.process.poll() is not None
                    chunk = reader.read()
                    if chunk:
                        print(chunk, end='', flush=True)
                        transcript += chunk
                        if required_markers:
                            for marker in re.findall(r'VOICE_[A-Z_]+', transcript):
                                if marker in required_markers and marker not in seen:
                                    expected = PERMISSION_ORDER[len(seen)]
                                    if marker != expected:
                                        raise RuntimeError('Unexpected native permission marker order: ' + marker)
                                    self.permission_marker(marker)
                                    seen.add(marker)
                    if exited:
                        break
                    time.sleep(.15)
            result = self.process.wait(timeout=5)
            record = self.evidence['suites'][name]
            record.update({'flutter_exit': result, 'observed_markers': sorted(seen)})
            if result:
                raise RuntimeError('Flutter ' + name + ' assertions failed; inspect ' + str(log_path))
            if required_markers and seen != required_markers:
                raise RuntimeError('Missing permission stages: ' + str(sorted(required_markers - seen)))
            if 'All tests passed!' not in transcript:
                raise RuntimeError('Flutter did not report successful assertions for ' + name)
            self.capture(name + '-completed')
            leftovers = self.shell('run-as', PACKAGE, 'sh', '-c',
                                   'if [ -d cache/voice ]; then ls -A cache/voice; fi').strip()
            record['voice_cache_empty'] = not leftovers
            if leftovers:
                raise RuntimeError('Voice temporary files remained after ' + name + ': ' + leftovers)
            return transcript
        finally:
            self.stop_process()
            self.deadline = None
            self.evidence['suites'][name]['duration_seconds'] = round(time.monotonic() - started, 2)
            if self.process is not None:
                self.evidence['suites'][name]['flutter_exit'] = self.process.returncode


PERMISSION_ORDER = ('VOICE_DENY_READY', 'VOICE_GRANT_READY',
                    'VOICE_BACKGROUND_READY', 'VOICE_BACKGROUND_CANCELLED')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, default=REPO / 'build/native-voice-review')
    parser.add_argument('--timeout', type=int, default=900,
                        help='Maximum seconds per Flutter suite, including its build (default: 900)')
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.device):
        parser.error('--device must be a disposable phone emulator, never a phone or TV')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    driver = Driver(args.device, output, args.timeout)
    try:
        if driver.shell('getprop', 'ro.kernel.qemu').strip() != '1':
            raise RuntimeError('Target is not an emulator; refusing permission changes')
        characteristics = driver.shell('getprop', 'ro.build.characteristics').strip()
        features = driver.shell('pm', 'list', 'features')
        if 'tv' in characteristics.lower() or 'android.software.leanback' in features:
            raise RuntimeError('TV emulator is outside this phone-native voice check')
        if not driver.shell('pm', 'path', PACKAGE).strip().startswith('package:'):
            raise RuntimeError('Install the normal debug dev APK on the disposable AVD first')
        driver.evidence.update({
            'source_revision': subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, timeout=10).strip(),
            'source_dirty': bool(subprocess.check_output(
                ['git', 'status', '--porcelain'], cwd=REPO, text=True, timeout=10).strip()),
            'android_release': driver.shell('getprop', 'ro.build.version.release').strip(),
            'android_sdk': driver.shell('getprop', 'ro.build.version.sdk').strip(),
            'device_model': driver.shell('getprop', 'ro.product.model').strip(),
            'characteristics': characteristics,
        })
        driver.shell('am', 'force-stop', PACKAGE)
        driver.shell('pm', 'revoke', PACKAGE, PERMISSION)
        driver.shell('pm', 'clear-permission-flags', PACKAGE, PERMISSION, 'user-set', 'user-fixed')
        if driver.granted():
            raise RuntimeError('Microphone permission reset did not take effect')
        driver.evidence['microphone_reset'] = True
        driver.run_suite('permission', 'integration_test/voice_permission_native_test.dart', PERMISSION_STEPS)
        driver.shell('pm', 'grant', PACKAGE, PERMISSION)
        if not driver.granted():
            raise RuntimeError('Microphone permission is not granted before native capture suite')
        transcript = driver.run_suite('native', 'integration_test/voice_native_test.dart')
        capabilities = re.search(
            r'VOICE_CAPABILITIES localInput=(true|false) languages=(.*?) offlineVoices=(\d+)', transcript)
        offline = re.search(r'VOICE_OFFLINE_VOICES (\d+)', transcript)
        if capabilities is None or offline is None:
            raise RuntimeError('Native voice capability evidence was not emitted')
        samples = re.findall(
            r'VOICE_LOCAL_TTS sample=(\d+) firstAudioMs=(\d+) completedMs=(\d+) voice=([^\r\n]+)', transcript)
        driver.evidence['capabilities'] = {
            'recognition_available': capabilities[1] == 'true',
            'installed_languages': capabilities[2], 'offline_voice_count': int(offline[1]),
        }
        driver.evidence['tts_callbacks'] = [
            {'sample': int(sample), 'start_callback_ms': int(start),
             'completed_ms': int(completed), 'voice': voice}
            for sample, start, completed, voice in samples
        ]
        if int(offline[1]) > 0 and sorted(int(s[0]) for s in samples) != list(range(5)):
            raise RuntimeError('Installed offline voice did not complete all five TTS samples')
        if int(offline[1]) == 0:
            driver.evidence['limitations'].append('No installed offline Android voice; five TTS samples unavailable.')
        if capabilities[1] == 'false':
            driver.evidence['limitations'].append('Android local speech recognition unavailable; rejection path exercised.')
        driver.evidence['limitations'].extend(re.findall(r'VOICE_LIMITATION ([^\r\n]+)', transcript))
        driver.evidence['status'] = 'passed'
        print('PASS: native microphone denial/grant, background cancellation, AAC capture and playback boundaries')
    except Exception as error:
        driver.evidence['status'] = 'failed'
        driver.evidence['error'] = str(error)
        raise
    finally:
        driver.stop_process()
        try:
            if driver.evidence.get('microphone_reset'):
                driver.shell('rm', '-f', driver.dump_path)
        except Exception as error:
            driver.evidence['status'] = 'failed'
            driver.evidence['cleanup_error'] = str(error)
            raise
        finally:
            (output / 'acceptance.json').write_text(json.dumps(driver.evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
