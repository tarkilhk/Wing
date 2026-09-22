#!/usr/bin/env python3
"""Check first structured notification without opening its chat, on QA emulator."""
import argparse
import json
import re
import subprocess
import time
import urllib.request

PACKAGE = 'com.tarkilhk.wing.notificationqa'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--port', type=int, default=18767)
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        parser.error('This check only runs on an isolated QA emulator.')
    adb = ['adb', '-s', args.serial]

    def command(*parts):
        return subprocess.check_output(adb + list(parts), text=True, timeout=20)

    command('forward', f'tcp:{args.port}', 'tcp:18766')

    def post(path):
        req = urllib.request.Request(f'http://127.0.0.1:{args.port}/{path}', data=b'{}')
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)

    assert post('state')['openedChat'] is None
    post('work')
    for _ in range(30):
        services = command('shell', 'dumpsys', 'activity', 'services', PACKAGE)
        if 'BackgroundMonitoringService' in services:
            break
        time.sleep(.25)
    else:
        raise AssertionError('Monitoring did not start during the unopened task')
    command('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    state = post('question')
    assert state['openedChat'] is None, state
    notice = None
    for _ in range(30):
        raw = command('shell', 'dumpsys', 'notification', '--noredact')
        matching = [block for block in re.split(r'(?=NotificationRecord\()', raw)
                    if re.match(r'NotificationRecord\([^\n]*pkg=' + re.escape(PACKAGE) + r'\b', block)
                    and 'channel=wing_attention_notifications' in block.splitlines()[0]]
        if matching:
            assert len(matching) == 1, 'More than one input notice'
            notice = matching[0]
            break
        time.sleep(.25)
    assert notice is not None, f'No first input notification; client state: {state}'
    for field in ['text', 'bigText']:
        found = re.search(r'android\.' + field + r'=String \((.*?)\)\n', notice, re.S)
        assert found, field
        assert all(text in found.group(1) for text in ['3 questions', 'WING-COLD-QA', 'Preview', 'Production']), found.group(1)
    assert 'Review' in notice, 'Missing Review action'
    assert 'ONLY_ALERT_ONCE' not in notice.splitlines()[0], 'Fresh request was rendered silently'
    assert post('state')['openedChat'] is None
    print('PASS: unopened chat posts one fresh native notification with 3 questions, real text/options and Review')
    for _ in range(30):
        services = command('shell', 'dumpsys', 'activity', 'services', PACKAGE)
        if 'BackgroundMonitoringService' not in services:
            break
        time.sleep(.25)
    else:
        raise AssertionError('Monitoring stayed alive after input became pending')
    print('PASS: monitoring stopped after posting the pending request')


if __name__ == '__main__':
    main()
