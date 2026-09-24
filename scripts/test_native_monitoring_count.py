#!/usr/bin/env python3
"""Assert one real Android monitoring card using the isolated notification QA app."""
import argparse
import json
import re
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--port', type=int, default=18767)
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    parser.error('Use the isolated emulator fixture, never a personal phone.')


def post(path):
    request = urllib.request.Request(
        f'http://127.0.0.1:{args.port}/{path}', data=b'{}',
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


post('list')
post('work')
subprocess.run(['adb', '-s', args.serial, 'shell', 'input', 'keyevent', '3'], check=True)
# Android may defer initially displaying an FGS notification. Count only active
# records, and wait for the first; an extra summary is still an immediate failure.
for _ in range(30):
    dump = subprocess.check_output(
        ['adb', '-s', args.serial, 'shell', 'dumpsys', 'notification', '--noredact'],
        text=True, timeout=15,
    )
    records = [
        part.splitlines()[0]
        for part in re.split(r'(?=NotificationRecord\()', dump)
        if re.match(r'NotificationRecord\([^\n]*pkg=com\.tarkilhk\.wing\.notificationqa\b', part)
        and 'channel=hermes_monitoring' in part.splitlines()[0]
    ]
    if records:
        break
    time.sleep(.5)
assert len(records) == 1, f'Expected one monitoring card, got {len(records)}'
assert 'id=214601 ' in records[0], records
assert 'FOREGROUND_SERVICE' in records[0], records
print('PASS: one foreground monitoring notification, no duplicate summary')
