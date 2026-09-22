#!/usr/bin/env python3
"""Verify an unread QA reply is restored silently after Android force-stop.

Install integration_test/notification_revamp_device.dart built with
notificationQa=true on an emulator, grant notifications and launch it first.
The fixture, not a real Hermes server, generates the test reply. Never targets
Wing's production package or a personal device.
"""

import argparse
import json
import re
import subprocess
import time
import urllib.request
import xml.etree.ElementTree as ET

PACKAGE = 'com.tarkilhk.wing.notificationqa'
ACTIVITY = f'{PACKAGE}/com.tarkilhk.wing.MainActivity'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--port', type=int, default=18767)
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        parser.error('Use an isolated emulator, never a personal device.')
    adb = ['adb', '-s', args.serial]

    def command(*parts):
        return subprocess.check_output(adb + list(parts), text=True, timeout=20)

    command('forward', f'tcp:{args.port}', 'tcp:18766')

    def request(path, body):
        req = urllib.request.Request(
            f'http://127.0.0.1:{args.port}/{path}',
            data=json.dumps(body).encode(),
            headers={'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)

    # A distinct event avoids reusing any previous run's dismissal/read ledger.
    answer = f'WING-RESTORE-QA-{time.time_ns()}: Unread result ready.'

    def notices(only_answer=True):
        dump = command('shell', 'dumpsys', 'notification', '--noredact')
        result = {}
        for block in re.split(r'(?=NotificationRecord\()', dump):
            if not re.match(
                r'NotificationRecord\([^\n]*pkg=' + re.escape(PACKAGE) + r'\b',
                block,
            ):
                continue
            head = block.splitlines()[0]
            if 'channel=wing_turn_notifications' not in head:
                continue
            fields = {}
            for field in ['text', 'bigText']:
                found = re.search(
                    r'android\.' + field + r'=String \((.*?)\)\n', block, re.S,
                )
                if found:
                    fields[field] = found.group(1)
            if not only_answer or fields.get('text') == answer:
                identifier = int(re.search(r'\bid=(\d+)', head).group(1))
                result[identifier] = {'head': head, **fields}
        return result

    def wait_for_notice():
        for _ in range(60):
            found = notices()
            if found:
                return found
            time.sleep(.25)
        return {}

    def ready():
        for _ in range(30):
            try:
                return request('', {})
            except OSError:
                time.sleep(.5)
        raise AssertionError('QA fixture did not restart')

    ready()
    request('preview', {'enabled': True})
    request('reply', {'text': answer})
    before = wait_for_notice()
    assert len(before) == 1, f'Expected one newly posted QA reply: {before}'
    identifier = next(iter(before))
    assert before[identifier]['bigText'] == answer, before
    print('PASS: fresh unread QA reply appears in one notification slot', flush=True)

    command('shell', 'am', 'force-stop', PACKAGE)
    assert not notices(), 'Android did not remove the notification on force-stop'
    command('shell', 'am', 'start', '-n', ACTIVITY)
    restored = wait_for_notice()
    assert set(restored) == {identifier}, (
        f'Unread reply not restored to its original slot after relaunch: {restored}'
    )
    assert restored[identifier]['bigText'] == answer, restored
    head = restored[identifier]['head']
    assert 'ONLY_ALERT_ONCE' in head and 'SILENT' in head, head
    print('PASS: relaunch restores the same unread reply and ID silently', flush=True)

    def shade_target():
        command('shell', 'cmd', 'statusbar', 'expand-notifications')
        for _ in range(4):
            command('shell', 'rm', '-f', '/sdcard/wing-qa-restore.xml')
            command('shell', 'uiautomator', 'dump', '/sdcard/wing-qa-restore.xml')
            xml = command('shell', 'cat', '/sdcard/wing-qa-restore.xml')
            target = next((node for node in ET.fromstring(xml).iter('node')
                           if node.get('text') == 'Website refresh'), None)
            if target is not None:
                return list(map(int, re.findall(r'\d+', target.get('bounds'))))
            time.sleep(.5)
        raise AssertionError('QA reply not found in notification shade')

    ready()
    request('list', {})
    assert identifier in notices(), 'Opening only the list marked the answer read'
    x1, y1, x2, y2 = shade_target()
    command('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
    for _ in range(40):
        state = ready()
        if identifier not in notices(only_answer=False):
            assert state['chat_visible'] and state['selected_chat'], state
            break
        time.sleep(.25)
    else:
        raise AssertionError(f'Restored reply not cleared by reading via native tap: {state}')
    print('PASS: native notification tap from the chat list opens the answer and clears its notice', flush=True)
    command('shell', 'am', 'force-stop', PACKAGE)
    command('shell', 'am', 'start', '-n', ACTIVITY)
    ready()
    for _ in range(12):
        assert identifier not in notices(only_answer=False), 'Read reply resurrected'
        time.sleep(.25)
    print('PASS: read reply stays absent after another launch', flush=True)

    # A separate fresh result tests the actual Android delete intent.
    answer = f'WING-DISMISS-QA-{time.time_ns()}: Swipe this fresh result.'
    request('reply', {'text': answer})
    assert wait_for_notice(), 'Fresh dismissal sample did not arrive'
    x1, y1, x2, y2 = shade_target()
    width = int(re.search(r'(\d+)x\d+', command('shell', 'wm', 'size')).group(1))
    command(
        'shell', 'input', 'swipe', str(width // 8), str((y1 + y2) // 2),
        str(width - 5), str((y1 + y2) // 2), '300',
    )
    for _ in range(20):
        if identifier not in notices(only_answer=False):
            break
        time.sleep(.25)
    else:
        raise AssertionError('Swipe did not remove the QA notification')
    command('shell', 'cmd', 'statusbar', 'collapse')
    command('shell', 'am', 'force-stop', PACKAGE)
    command('shell', 'am', 'start', '-n', ACTIVITY)
    for _ in range(30):
        try:
            request('', {})
            break
        except OSError:
            time.sleep(.5)
    else:
        raise AssertionError('QA fixture did not restart')
    for _ in range(12):
        assert identifier not in notices(only_answer=False), (
            'Explicitly dismissed reply resurrected after relaunch'
        )
        time.sleep(.25)
    command('shell', 'rm', '-f', '/sdcard/wing-qa-restore.xml')
    print('PASS: explicitly swiped reply stays absent after another relaunch', flush=True)


if __name__ == '__main__':
    main()
