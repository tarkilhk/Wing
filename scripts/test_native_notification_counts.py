#!/usr/bin/env python3
"""Check real Android rendering against the isolated notification QA fixture.

Build integration_test/notification_revamp_device.dart with notificationQa=true,
install only on an emulator, grant notifications, launch it, and forward the
fixture's port 18766. This script never targets the production Wing package.
"""

import argparse
import json
import re
import subprocess
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--port', type=int, default=18767)
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        parser.error('Use an isolated emulator, never a personal device.')

    def post(path, body):
        request = urllib.request.Request(
            f'http://127.0.0.1:{args.port}/{path}',
            data=json.dumps(body).encode(),
            headers={'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.load(response)

    def texts():
        dump = subprocess.check_output(
            ['adb', '-s', args.serial, 'shell', 'dumpsys', 'notification', '--noredact'],
            text=True,
            timeout=15,
        )
        result = {}
        for block in re.split(r'(?=NotificationRecord\()', dump):
            if not re.match(
                r'NotificationRecord\([^\n]*pkg=com\.tarkilhk\.wing\.notificationqa\b',
                block,
            ):
                continue
            if 'channel=wing_attention_notifications' not in block.splitlines()[0]:
                continue
            for field in ['text', 'bigText']:
                match = re.search(r'android\.' + field + r'=String \((.*?)\)\n', block, re.S)
                if match:
                    result[field] = match.group(1)
        return result

    post('preview', {'enabled': True})
    for count in [3, 2, 1]:
        post('question', {'count': count})
        expected = f'{count} question' + ('s' if count != 1 else '')
        for _ in range(20):
            rendered = texts()
            if all(expected in rendered.get(field, '') for field in ['text', 'bigText']):
                break
            time.sleep(.1)
        else:
            raise AssertionError(f'Missing visible {expected!r}: {rendered}')
        print(f'PASS: collapsed and expanded notification show {expected}', flush=True)

    post('preview', {'enabled': False})
    hidden = texts()
    assert all('1 question' in hidden.get(field, '') for field in ['text', 'bigText']), hidden
    assert not any(word in str(hidden) for word in ['Which sample', 'Summary', 'Checklist']), hidden
    print('PASS: hidden previews retain the count without exposing question content')


if __name__ == '__main__':
    main()
