#!/usr/bin/env python3
"""Exercise real Android file/share dialogs on a disposable, already booted AVD.

Usage: python3 scripts/test_native_file_transfer.py --device emulator-5580
Requires Flutter and adb on PATH. Screenshots and logs go to --output.
Never targets a physical device or connects to a Hermes server.
"""

import argparse
import pathlib
import re
import struct
import subprocess
import time
import xml.etree.ElementTree as ET
import zlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('/tmp/wing-file-transfer'))
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.device):
        parser.error('Use a disposable Android emulator, not a physical device.')
    args.output.mkdir(parents=True, exist_ok=True)

    def adb(*command, binary=False):
        return subprocess.check_output(
            ['adb', '-s', args.device, *command], text=not binary, timeout=30
        )

    def tap(node):
        left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
        adb('shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))

    def capture(label):
        (args.output / f'{label}.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))

    def drive(marker):
        filename = 'wing-native-probe.png' if marker == 'photo-select' else 'wing-native-probe.json'
        deadline = time.monotonic() + 50
        while time.monotonic() < deadline:
            adb('shell', 'uiautomator', 'dump', '/sdcard/wing-file-transfer.xml')
            xml = adb('shell', 'cat', '/sdcard/wing-file-transfer.xml')
            (args.output / f'{marker}.xml').write_text(xml)
            nodes = list(ET.fromstring(xml).iter('node'))
            if any(n.get('resource-id') == 'android:id/aerr_close' for n in nodes):
                capture(f'{marker}-anr')
                raise RuntimeError('Android reported an ANR; inspect the captured dialog before retrying.')
            external = [n for n in nodes if n.get('package') in {
                'com.google.android.documentsui', 'com.android.documentsui',
                'com.android.intentresolver', 'com.google.android.providers.media.module',
                'com.android.providers.media.module', 'com.google.android.photopicker', 'android',
            }]
            if not external:
                time.sleep(0.5)
                continue
            if marker.endswith('cancel'):
                if marker == 'share-cancel' and not any(
                    'wing-config-' in n.get('text', '') or 'Sharing' in n.get('text', '')
                    or 'share' in n.get('resource-id', '').lower() for n in external
                ):
                    time.sleep(0.5)
                    continue
                capture(marker)
                adb('shell', 'input', 'keyevent', '4')
                return
            match = next((n for n in external if n.get('text') == filename
                          or n.get('content-desc', '').startswith(filename + ', ')), None)
            if match is not None:
                capture(marker)
                tap(match)
                return
            if marker == 'photo-select':
                browse = next((n for n in external if n.get('text', '').startswith('Browse')), None)
                more = next((n for n in external if n.get('content-desc') == 'More'), None)
                if browse is not None or more is not None:
                    tap(browse if browse is not None else more)
                    time.sleep(0.5)
                    continue
            # Images may first open the Android source chooser.
            choice = next((n for n in external if n.get('text') in {'Files', 'Downloads'}), None)
            if choice is not None:
                tap(choice)
            else:
                drawer = next((n for n in external if n.get('content-desc') == 'Show roots'), None)
                if drawer is not None:
                    tap(drawer)
            time.sleep(0.5)
        capture(f'{marker}-failed')
        raise RuntimeError(f'Could not complete native dialog: {marker}')

    probe = args.output / 'wing-native-probe.json'
    probe.write_text('{"probe":"Wing native file transfer — ✓"}', encoding='utf-8')
    png = args.output / 'wing-native-probe.png'

    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

    png.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 32, 32, 8, 2, 0, 0, 0))
                   + chunk(b'IDAT', zlib.compress((b'\x00' + b'\x20\x90\xc0' * 32) * 32)) + chunk(b'IEND', b''))
    for path in [probe, png]:
        adb('push', str(path), f'/sdcard/Download/{path.name}')
        adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
            '-d', f'file:///sdcard/Download/{path.name}')

    command = ['flutter', 'test', 'integration_test/file_transfer_native_test.dart',
               '-d', args.device, '--reporter', 'expanded', '--no-uninstall']
    # Clear activities left by an interrupted run, only on the requested AVD.
    for package in ['com.tarkilhk.wing.dev', 'com.google.android.documentsui',
                    'com.android.documentsui', 'com.google.android.photopicker']:
        adb('shell', 'am', 'force-stop', package)
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    completed = set()
    try:
        with (args.output / 'flutter.log').open('w') as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                print(line, end='', flush=True)
                match = re.search(r'FILE_TRANSFER:([a-z-]+)', line)
                if match and match[1] not in completed:
                    drive(match[1])
                    completed.add(match[1])
        result = process.wait()
        if result or len(completed) != 6:
            raise SystemExit(result or 1)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        for path in [probe, png]:
            adb('shell', 'rm', '-f', f'/sdcard/Download/{path.name}')
        adb('shell', 'rm', '-f', '/sdcard/wing-file-transfer.xml')


if __name__ == '__main__':
    main()
