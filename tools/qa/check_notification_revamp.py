#!/usr/bin/env python3
"""Native smoke test for notification_revamp_device.dart, isolated emulator only."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.request
import xml.etree.ElementTree as ET

PACKAGE = 'com.tarkilhk.wing.notificationqa'
SERIAL = 'emulator-5556'


def adb(*args):
    return subprocess.check_output(['adb', '-s', SERIAL, *args], text=True, timeout=25)


def state(path='/', data=None):
    request = urllib.request.Request('http://127.0.0.1:18766' + path,
        data=None if data is None else json.dumps(data).encode(),
        headers={'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(request, timeout=5))


def until(check, message, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except (OSError, ValueError):
            pass
        time.sleep(.3)
    raise AssertionError(message)


def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/wing-notification-ui.xml')
    return list(ET.fromstring(adb('shell', 'cat', '/sdcard/wing-notification-ui.xml')).iter('node'))


def tap(resource=None, text=None):
    found = next((n for n in nodes() if
        (resource is not None and n.get('resource-id') == resource) or
        (text is not None and text in (n.get('text'), n.get('content-desc')))), None)
    assert found is not None, f'Missing control: {resource or text}'
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', found.get('bounds')))
    adb('shell', 'input', 'tap', str((x1 + x2)//2), str((y1 + y2)//2))


def shade():
    width, height = map(int, re.findall(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))[-1])

    def opened():
        # Use the real user gesture: some emulator System UI builds ignore the
        # shell expansion command. Wait for notification UI before tapping.
        adb('shell', 'cmd', 'statusbar', 'collapse')
        time.sleep(.3)
        adb('shell', 'input', 'swipe', str(width // 2), '1', str(width // 2), str(height * 2 // 3), '400')
        time.sleep(.7)
        shown = nodes()
        return shown if any(n.get('resource-id') == 'android:id/app_name_text' for n in shown) else None

    shown = until(opened, 'Notification shade did not open')
    button = next((n for n in shown if n.get('resource-id') == 'android:id/expand_button'), None)
    if button is not None and button.get('content-desc') == 'Expand':
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', button.get('bounds')))
        adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        time.sleep(.5)


def screenshot(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(subprocess.check_output(['adb', '-s', SERIAL, 'exec-out', 'screencap', '-p']))


def run(output):
    assert SERIAL.startswith('emulator-'), 'Use a disposable emulator, never a phone'
    adb('forward', 'tcp:18766', 'tcp:18766')
    adb('shell', 'pm', 'clear', PACKAGE)
    adb('shell', 'pm', 'grant', PACKAGE, 'android.permission.POST_NOTIFICATIONS')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    adb('shell', 'cmd', 'uimode', 'night', 'no')
    adb('shell', 'am', 'start', '-n', PACKAGE + '/com.tarkilhk.wing.MainActivity')
    until(lambda: state()['ready'], 'Fixture did not start')
    state('/work', {})
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    state('/approval', {})
    state('/approval', {'command': 'npm run release'})
    shade()
    screenshot(output / 'light-normal.png')
    tap(resource=PACKAGE + ':id/once')
    until(lambda: len(state()['decisions']) == 1, 'Once did not submit')
    assert state()['decisions'][0]['params']['request_id'] == 'qa-1'
    assert state()['pending'][0]['request_id'] == 'qa-2'
    print('PASS: Once resolves the exact head and advances FIFO', flush=True)
    state('/fail', {'enabled': True})
    shade()
    tap(resource=PACKAGE + ':id/once')
    until(lambda: len(state()['decisions']) == 2, 'Failure fixture did not receive attempt')
    assert state()['pending'][0]['request_id'] == 'qa-2'
    shade()
    assert any('not confirmed' in n.get('text', '') for n in nodes())
    screenshot(output / 'unconfirmed.png')
    print('PASS: failed submission retains notification and request', flush=True)
    state('/fail', {'enabled': False})
    tap(resource=PACKAGE + ':id/always')
    until(lambda: any('Always allow this command pattern?' in (n.get('text'), n.get('content-desc')) for n in nodes()), 'Missing permanent-pattern confirmation')
    assert len(state()['decisions']) == 2
    screenshot(output / 'always-confirmation.png')
    tap(text='Cancel')
    assert len(state()['decisions']) == 2
    print('PASS: Always opens the owning chat and requires confirmation', flush=True)
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    state('/preview', {'enabled': False})
    shade()
    shown = nodes()
    assert not any(n.get('resource-id') == PACKAGE + ':id/once' for n in shown)
    assert any(n.get('text') == 'Review' for n in shown)
    screenshot(output / 'private-preview.png')
    print('PASS: hidden previews expose Review only', flush=True)
    state('/preview', {'enabled': True})
    for night in ('no', 'yes'):
        for scale in ('1.0', '2.0'):
            adb('shell', 'settings', 'put', 'system', 'font_scale', scale)
            adb('shell', 'cmd', 'uimode', 'night', night)
            time.sleep(.7)
            shade()
            shown = nodes()
            for choice in ('once', 'session', 'always', 'deny'):
                assert any(n.get('resource-id') == PACKAGE + ':id/' + choice for n in shown), choice
            if scale == '2.0':
                controls = {choice: next(n for n in shown if n.get('resource-id') == PACKAGE + ':id/' + choice) for choice in ('once', 'session', 'always', 'deny')}
                bounds = {k: list(map(int, re.findall(r'\d+', n.get('bounds')))) for k, n in controls.items()}
                assert bounds['always'][1] >= bounds['once'][3], 'Large-text choices did not switch to two rows'
                assert all(b[3] - b[1] >= 120 for b in bounds.values()), 'Clipped approval target'
            screenshot(output / f"{'dark' if night == 'yes' else 'light'}-{scale}.png")
    print('PASS: all four controls remain available in both themes at 100%/200%', flush=True)
    state('/remote', {})
    until(lambda: all(not v['inputs'] for v in json.loads(state()['notices']).values()), 'Watcher did not clear remote decision')
    print('PASS: watcher reconciles a desktop decision without another notification tap', flush=True)
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    adb('shell', 'cmd', 'uimode', 'night', 'no')
    answer = 'The mobile layout is ready. Read the result before publishing.'
    state('/reply', {'text': answer})
    shade()
    screenshot(output / 'reply.png')
    tap(text=answer)
    until(lambda: all(v['result'] is None for k, v in json.loads(state()['notices']).items() if json.loads(k)['profile'] == 'a'), 'Reading the latest answer did not clear its notification')
    print('PASS: body tap opens latest reply and visibility clears its notification', flush=True)
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    state('/error', {})
    shade()
    screenshot(output / 'stopped.png')
    state('/stop', {})



if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default=SERIAL)
    parser.add_argument('--output', type=Path, default=Path('build/notification-review'))
    args = parser.parse_args()
    SERIAL = args.serial
    try:
        run(args.output)
    finally:
        if SERIAL.startswith('emulator-'):
            adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
            adb('shell', 'cmd', 'uimode', 'night', 'no')
