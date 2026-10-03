#!/usr/bin/env python3
"""Native smoke test for notification_revamp_device.dart, isolated emulator only."""
import argparse
import json
from pathlib import Path
import re
import shlex
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
        # A second pull can open Quick Settings instead of notifications.
        # Return to Home first so retries always start with a closed panel.
        adb('shell', 'input', 'keyevent', 'KEYCODE_BACK', 'KEYCODE_BACK', 'KEYCODE_HOME')
        time.sleep(.5)
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


def check_untrusted_main_intents():
    before = state()
    notices = json.loads(before['notices'])
    notice = next(value for value in notices.values()
                  if value['inputs'] and value['inputs'][0]['focus']['kind'] == 'approval')
    rendered = json.loads(notice['rendered'])
    # Use the exact live target and revision: rejection must come from the
    # exported entry point's authorization boundary, not a stale chat lookup.
    interaction = json.dumps({
        'payload': rendered['payload'], 'choice': 'once', 'review': False,
        'chat': rendered['chat'], 'revision': rendered['revision'],
        'notification_id': rendered['id'],
    })
    pid = adb('shell', 'pidof', PACKAGE).strip()
    attempts = [
        ('--es', 'wing_notification_interaction', interaction),
        ('--es', 'wing_notification_interaction', '{'),
        ('--es', 'wing_notification_handle', '00000000-0000-0000-0000-000000000000'),
        ('--es', 'wing_notification_handle', interaction),
        ('--ei', 'wing_notification_handle', '7'),
    ]
    for kind, extra, value in attempts:
        command = ['am', 'start', '-W', '-n', PACKAGE + '/com.tarkilhk.wing.MainActivity',
                   '-f', '0x30000000', kind, extra, value]
        # adb shell joins arguments before remote shell parsing. Quote the JSON
        # there so Android receives one complete extra with its actual spaces.
        adb('shell', shlex.join(command))
        for _ in range(3):
            time.sleep(.4)
            after = state()
            assert after['decisions'] == before['decisions'], 'Forged main intent submitted a decision'
            assert after['pending'] == before['pending'], 'Forged main intent changed pending approvals'
            assert after['selected_chat'] == before['selected_chat'], 'Forged main intent navigated to a chat'
        assert adb('shell', 'pidof', PACKAGE).strip() == pid, 'Untrusted main intent crashed/restarted Wing'
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    print('PASS: exported MainActivity rejects raw, forged and wrong-type notification inputs without decisions or crashes', flush=True)


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
    check_untrusted_main_intents()
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
    until(lambda: any('Always allow?' in (n.get('text'), n.get('content-desc')) for n in nodes()), 'Missing permanent-pattern confirmation')
    assert len(state()['decisions']) == 2
    screenshot(output / 'always-confirmation.png')
    tap(text='Cancel')
    assert len(state()['decisions']) == 2
    print('PASS: Always requires confirmation for the owning request', flush=True)
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
    check_direct_actions(output)
    # A settled cold action may release its engine; restart this fake app for
    # the unrelated reply/open checks that follow.
    adb('shell', 'am', 'start', '-n', PACKAGE + '/com.tarkilhk.wing.MainActivity')
    until(lambda: state()['ready'], 'Fixture did not restart after the cold action')
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
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



def check_direct_actions(output):
    state('/fail', {'enabled': False})
    state('/preview', {'enabled': True})
    state('/remote', {})
    until(lambda: all(not v['inputs'] for v in json.loads(state()['notices']).values()), 'Old requests did not clear')
    for choice in ('session', 'deny'):
        before = len(state()['decisions'])
        state('/approval', {'command': 'echo ok'})
        shade()
        tap(resource=PACKAGE + ':id/' + choice)
        until(lambda: len(state()['decisions']) == before + 1, f'{choice} did not submit directly')
        assert state()['decisions'][-1]['params']['choice'] == choice
        assert not any('Review command' in (n.get('text'), n.get('content-desc')) for n in nodes())
    print('PASS: Session and Deny complete without another confirmation', flush=True)
    long_command = 'echo ' + 'long-command-argument-' * 50
    state('/approval', {'command': long_command})
    before = len(state()['decisions'])
    for night in ('no', 'yes'):
        for scale in ('1.0', '2.0'):
            adb('shell', 'settings', 'put', 'system', 'font_scale', scale)
            adb('shell', 'cmd', 'uimode', 'night', night)
            time.sleep(.7)
            shade()
            shown = nodes()
            assert any(n.get('resource-id') == PACKAGE + ':id/review' for n in shown)
            assert any(n.get('resource-id') == PACKAGE + ':id/review_deny' for n in shown)
            assert not any(n.get('resource-id') == PACKAGE + ':id/' + choice for n in shown
                           for choice in ('once', 'session', 'always'))
            screenshot(output / f"truncated-{'dark' if night == 'yes' else 'light'}-{scale}.png")
    tap(resource=PACKAGE + ':id/review')
    until(lambda: any('Allow once' in (n.get('text'), n.get('content-desc')) for n in nodes()), 'Review did not open command choices')
    assert len(state()['decisions']) == before, 'Review submitted a decision'
    adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    shade()
    tap(resource=PACKAGE + ':id/review_deny')
    until(lambda: len(state()['decisions']) == before + 1, 'Truncated command Deny did not submit')
    assert state()['decisions'][-1]['params']['choice'] == 'deny'
    print('PASS: truncated commands expose Review and direct Deny in both themes and text sizes', flush=True)
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    adb('shell', 'cmd', 'uimode', 'night', 'no')
    check_cold_action(output)




def check_cold_action(output):
    def saved_decisions():
        # A settled action releases the fake HTTP server with its engine.
        # Read the fake server's acknowledgement persisted before its RPC reply.
        root = ET.fromstring(adb('shell', 'run-as', PACKAGE, 'cat',
                                 'shared_prefs/FlutterSharedPreferences.xml'))
        value = next(n.text for n in root if n.get('name') == 'flutter.notification_qa_decisions')
        return json.loads(value)

    state('/approval', {'command': 'echo ok'})
    before = len(state()['decisions'])
    cold_request = state()['pending'][0]['request_id']
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    pid = adb('shell', 'pidof', PACKAGE).strip()
    adb('shell', 'run-as', PACKAGE, 'kill', '-9', pid)
    until(lambda: not adb('shell', f'pidof {PACKAGE} || true').strip(), 'Fixture did not stop')
    shade()
    tap(resource=PACKAGE + ':id/once')
    until(lambda: len(saved_decisions()) == before + 1, 'Cold Once did not submit')
    assert saved_decisions()[-1]['params']['request_id'] == cold_request
    until(lambda: not any(PACKAGE in line for line in adb('shell', 'dumpsys', 'activity', 'activities').splitlines()
                          if 'topResumedActivity=' in line), 'Cold action left Wing in front')
    assert not any('Review command' in (n.get('text'), n.get('content-desc')) for n in nodes())
    screenshot(output / 'cold-return.png')
    print('PASS: cold Once submits the exact request and returns to the previous screen', flush=True)


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
