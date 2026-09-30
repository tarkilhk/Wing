#!/usr/bin/env python3
"""Check production inbound URI handling with another UID on a disposable emulator.

Build/install/launch notification_revamp_device.dart first. This check sends no
Hermes messages. It builds a standalone SDK-only sender/provider APK, inspects
only synthetic intake bytes, and removes its helper and owned files afterward.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile


PACKAGE = 'com.tarkilhk.wing.notificationqa'
HELPER = 'com.tarkilhk.wing.shareqa.fixture'
CONTENTS = 'Wing external share boundary — ✓\n'.encode()
MARKER = 'cache/delivered_outputs/share-boundary-marker.txt'
PREFERENCES = 'shared_prefs/pending_share_intake.xml'
REPO = Path(__file__).resolve().parents[2]


def execute(command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, timeout=90, **kwargs)


def build_helper(sdk, java_home, output):
    tools = sdk / 'build-tools/36.0.0'
    android_jar = sdk / 'platforms/android-36/android.jar'
    fixture = REPO / 'integration_test/fixtures/external_share'
    for path in [android_jar, *[tools / name for name in ('aapt2', 'd8', 'zipalign', 'apksigner')],
                 *[java_home / 'bin' / name for name in ('java', 'javac', 'keytool')]]:
        if not path.is_file():
            raise RuntimeError(f'Required SDK/JDK tool is missing: {path}')
    env = dict(os.environ, JAVA_HOME=str(java_home))
    env['PATH'] = str(java_home / 'bin') + os.pathsep + env.get('PATH', '')
    output.mkdir(parents=True, exist_ok=True)
    apk = output / 'external-share-fixture.apk'
    with tempfile.TemporaryDirectory(prefix='external-share-build-', dir=output) as temporary:
        scratch = Path(temporary)
        classes = scratch / 'classes'
        dex = scratch / 'dex'
        classes.mkdir()
        dex.mkdir()
        execute([java_home / 'bin/javac', '-encoding', 'UTF-8', '-source', '8', '-target', '8',
                 '-classpath', android_jar, '-d', classes, *sorted(fixture.glob('*.java'))], env=env)
        jar = scratch / 'classes.jar'
        with zipfile.ZipFile(jar, 'w') as archive:
            for path in classes.rglob('*.class'):
                archive.write(path, path.relative_to(classes))
        execute([tools / 'd8', '--lib', android_jar, '--min-api', '24', '--output', dex, jar], env=env)
        unsigned = scratch / 'unsigned.apk'
        execute([tools / 'aapt2', 'link', '-I', android_jar, '--manifest', fixture / 'AndroidManifest.xml',
                 '--min-sdk-version', '24', '--target-sdk-version', '36', '--version-code', '1',
                 '--version-name', '1', '-o', unsigned], env=env)
        with zipfile.ZipFile(unsigned, 'a', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in dex.glob('*.dex'):
                archive.write(path, path.name)
        aligned = scratch / 'aligned.apk'
        execute([tools / 'zipalign', '-f', '4', unsigned, aligned], env=env)
        key = scratch / 'fixture.jks'
        password = uuid.uuid4().hex
        execute([java_home / 'bin/keytool', '-genkeypair', '-keystore', key, '-storepass', password,
                 '-keypass', password, '-alias', 'fixture', '-dname', 'CN=Disposable Wing QA',
                 '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2', '-noprompt'], env=env,
                stdout=subprocess.DEVNULL)
        execute([tools / 'apksigner', 'sign', '--ks', key, '--ks-key-alias', 'fixture',
                 '--ks-pass', 'pass:' + password, '--key-pass', 'pass:' + password,
                 '--out', apk, aligned], env=env)
        execute([tools / 'apksigner', 'verify', apk], env=env)
    return apk


class Device:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *parts, binary=False, input_bytes=None):
        result = execute(['adb', '-s', self.serial, *parts], capture_output=True,
                         input=input_bytes)
        return result.stdout if binary else result.stdout.decode()

    def shell(self, *parts):
        return self.adb('shell', shlex.join(parts))

    def private_read(self, package, path):
        return self.adb('exec-out', 'run-as', package, 'cat', path, binary=True)

    def installed(self, package):
        return 'package:' + package in self.shell('pm', 'list', 'packages', package).splitlines()

    def private_exists(self, package, path):
        return self.shell('run-as', package, 'sh', '-c',
                          'if [ -e ' + shlex.quote(path) + ' ]; then echo yes; fi').strip() == 'yes'

    def private_write(self, path, data):
        # run-as receives its own shell script as one argument; stdin is bytes.
        command = shlex.join(['run-as', PACKAGE, 'sh', '-c', 'cat > ' + shlex.quote(path)])
        self.adb('shell', command, input_bytes=data)

    def preferences(self, package, name):
        path = 'shared_prefs/' + name + '.xml'
        if not self.private_exists(package, path):
            return {}
        root = ET.fromstring(self.private_read(package, path))
        return {entry.get('name'): entry.text if entry.tag == 'string' else entry.get('value')
                for entry in root}

    def intake(self):
        preferences = self.preferences(PACKAGE, 'pending_share_intake')
        queue = json.loads(preferences.get('queue', '[]'))
        files = self.shell('run-as', PACKAGE, 'sh', '-c',
                           'if [ -d files/pending_intake ]; then find files/pending_intake -type f; fi')
        return queue, sorted(files.splitlines()), preferences.get('pending_camera')

    def observations(self):
        prefs = self.preferences(HELPER, 'probe')
        return {operation: int(prefs.get(operation, '0')) for operation in ('type', 'query', 'open')}


def until(check, message, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.2)
    raise AssertionError(message)


def run(serial, apk, output):
    if not re.fullmatch(r'emulator-\d+', serial):
        raise RuntimeError('Use a disposable emulator, never a physical device.')
    device = Device(serial)
    assert device.shell('getprop', 'ro.kernel.qemu').strip() == '1', 'Device is not an emulator'
    assert device.installed(PACKAGE), 'Install the isolated notification QA target first'
    assert not device.installed(HELPER), 'Remove the previous owned share fixture first'
    # The native QA entry point is intentionally kept running: warm SEND reaches
    # MainActivity's real intake path even though this target has no share UI.
    pid = device.shell('pidof', PACKAGE).strip()
    assert pid, 'Launch notification_revamp_device.dart before running this check'
    initial = device.intake()
    assert initial == ([], [], None), 'QA intake must be empty, with no pending camera or files'
    initial_directories = device.shell('run-as', PACKAGE, 'sh', '-c',
                                      'if [ -d files/pending_intake ]; then find files/pending_intake -mindepth 1; fi')
    assert not initial_directories.strip(), 'QA intake directory must have no previous fixture entries'
    assert not device.private_exists(PACKAGE, MARKER), 'Owned marker path already exists'
    prefs_existed = device.private_exists(PACKAGE, PREFERENCES)
    previous_prefs = device.private_read(PACKAGE, PREFERENCES) if prefs_existed else None
    intake_existed = device.private_exists(PACKAGE, 'files/pending_intake')
    marker_directory_existed = device.private_exists(PACKAGE, 'cache/delivered_outputs')
    installed = False
    marker_created = False
    evidence = []
    try:
        device.adb('install', '--no-incremental', apk.as_posix())
        installed = True
        assert device.shell('run-as', HELPER, 'id', '-u').strip() != device.shell('run-as', PACKAGE, 'id', '-u').strip(), 'Provider must run under a foreign UID'
        device.shell('run-as', PACKAGE, 'mkdir', '-p', 'cache/delivered_outputs')
        device.private_write(MARKER, b'Owned Wing private-file rejection marker\n')
        marker_created = True

        def unchanged(label, previous_intake, previous_counts):
            # Native intake is asynchronous. Repeated checks also catch deferred
            # copies; the subsequent granted case proves the same path executes.
            for _ in range(6):
                time.sleep(.35)
                assert device.intake() == previous_intake, label + ': intake changed'
                assert device.observations() == previous_counts, label + ': provider was touched'
                assert device.shell('pidof', PACKAGE).strip() == pid, label + ': Wing crashed/restarted'
            evidence.append({'scenario': label, 'provider': previous_counts, 'accepted': False})
            print('PASS: ' + label + ' rejected before provider access or intake changes', flush=True)

        def send(mode):
            nonce = uuid.uuid4().hex
            device.shell('am', 'start', '-W', '-n', HELPER + '/.ShareSenderActivity',
                         '--es', 'mode', mode, '--es', 'nonce', nonce)
            def sent():
                status = device.preferences(HELPER, 'sender')
                assert not status.get('error'), 'Android rejected fixture dispatch: ' + str(status)
                return status.get('sent') == mode + ':' + nonce
            until(sent, 'Fixture did not dispatch ' + mode)

        counts = device.observations()
        for label, uri in [
            ('file URI', 'file:///data/user/0/' + PACKAGE + '/' + MARKER),
            ('own provider URI', 'content://' + PACKAGE + '.fileprovider/delivered_outputs/share-boundary-marker.txt'),
        ]:
            device.shell('am', 'start', '-W', '-n', PACKAGE + '/com.tarkilhk.wing.MainActivity',
                         '-a', 'android.intent.action.SEND', '-t', 'text/plain',
                         '--eu', 'android.intent.extra.STREAM', uri)
            unchanged(label, initial, counts)

        send('no-grant')
        unchanged('foreign URI without read grant', initial, counts)
        send('mixed')
        unchanged('granted foreign plus own-provider batch', initial, counts)

        send('grant')
        accepted = until(lambda: device.intake()[0], 'Granted foreign URI was not imported')
        assert len(accepted) == 1 and len(accepted[0]['files']) == 1, 'Unexpected intake records/files'
        incoming = accepted[0]['files'][0]
        assert incoming['name'] == 'wing-share-probe.txt'
        assert incoming['mediaType'] == 'text/plain'
        assert incoming['byteLength'] == len(CONTENTS)
        assert device.private_read(PACKAGE, incoming['path']) == CONTENTS, 'Imported bytes differ'
        counts = device.observations()
        assert counts['query'] > 0 and counts['open'] == 1 and counts['type'] > 0, counts
        evidence.append({'scenario': 'granted foreign URI', 'provider': counts,
                         'accepted': True, 'bytes': len(CONTENTS)})
        assert device.private_read(PACKAGE, MARKER) == b'Owned Wing private-file rejection marker\n'
        print('PASS: granted foreign URI imports exact UTF-8 bytes through the real provider', flush=True)
        (output / 'acceptance.json').write_text(json.dumps(evidence, indent=2) + '\n')
    finally:
        # Stop only the synthetic QA process before restoring its native prefs,
        # so its cached SharedPreferences cannot overwrite the restored file.
        try:
            if installed or marker_created:
                device.shell('am', 'force-stop', PACKAGE)
                directories = device.shell('run-as', PACKAGE, 'sh', '-c',
                                           'if [ -d files/pending_intake ]; then find files/pending_intake -mindepth 1 -maxdepth 1 -type d; fi')
                for directory in directories.splitlines():
                    assert re.fullmatch(r'files/pending_intake/[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}', directory), 'Unexpected owned intake path'
                    device.shell('run-as', PACKAGE, 'rm', '-rf', directory)
                if previous_prefs is None:
                    device.shell('run-as', PACKAGE, 'rm', '-f', PREFERENCES)
                else:
                    device.private_write(PREFERENCES, previous_prefs)
                if marker_created:
                    device.shell('run-as', PACKAGE, 'rm', '-f', MARKER)
                if not intake_existed:
                    device.shell('run-as', PACKAGE, 'sh', '-c', 'rmdir files/pending_intake 2>/dev/null || true')
                if not marker_directory_existed:
                    device.shell('run-as', PACKAGE, 'sh', '-c', 'rmdir cache/delivered_outputs 2>/dev/null || true')
                assert device.intake() == initial, 'Native intake cleanup did not restore its empty baseline'
        finally:
            if installed:
                device.adb('uninstall', HELPER)
                assert not device.installed(HELPER), 'Helper remained installed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', REPO.parent / '.toolchain/android-sdk')))
    parser.add_argument('--java-home', type=Path, default=Path(os.environ.get('JAVA_HOME', REPO.parent / '.toolchain/jdk')))
    parser.add_argument('--output', type=Path, default=REPO / 'build/external-share-review')
    args = parser.parse_args()
    if not args.build_only and (not args.serial or not re.fullmatch(r'emulator-\d+', args.serial)):
        parser.error('--serial must identify a disposable emulator')
    apk = build_helper(args.sdk.resolve(), args.java_home.resolve(), args.output.resolve())
    print('Built owned fixture: ' + str(apk), flush=True)
    if not args.build_only:
        run(args.serial, apk, args.output.resolve())


if __name__ == '__main__':
    main()
