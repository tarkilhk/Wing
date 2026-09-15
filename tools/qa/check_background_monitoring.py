#!/usr/bin/env python3
"""Assert native notification delivery on an emulator, including forced Doze.

Build/install integration_test/background_monitoring_device.dart first.
This fixture must never be installed over a user's production app.
"""
import argparse
import json
import re
import subprocess
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--port', type=int, default=18765)
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        raise SystemExit('This test changes device power settings; use an emulator.')
    package = 'com.tarkilhk.wing.dev'

    def adb(*parts):
        return subprocess.check_output(['adb', '-s', args.serial, *parts], text=True)

    def shell(*parts):
        return adb('shell', *parts)

    def request(path='/status', body=None):
        return json.load(urllib.request.urlopen(urllib.request.Request(
            f'http://127.0.0.1:{args.port}{path}',
            data=body.encode() if body is not None else None,
        ), timeout=15))

    def until(action, message, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = action()
                if value:
                    return value
            except (OSError, ValueError):
                pass
            time.sleep(.25)
        raise AssertionError(message)

    def foreground():
        return 'isForeground=true' in shell('dumpsys', 'activity', 'services', package)

    def notification_present(number):
        dump = shell('dumpsys', 'notification', '--noredact')
        return bool(re.search(
            rf'NotificationRecord\([^\n]*pkg={re.escape(package)}[^\n]*id={number}\b', dump))

    def notification_identity(number):
        dump = shell('dumpsys', 'notification', '--noredact')
        for record in re.split(r'(?=^[ \t]*NotificationRecord\()', dump, flags=re.MULTILINE):
            if not re.search(
                    rf'NotificationRecord\([^\n]*pkg={re.escape(package)}[^\n]*id={number}\b',
                    record):
                continue
            icon = re.search(r'icon=Icon\([^\n]*id=([^\s)]+)', record)
            group = re.search(r'^\s*groupKey=(.+)$', record, re.MULTILINE)
            if icon and group:
                return icon.group(1), group.group(1).strip()
        return None

    def launch():
        shell('am', 'start', '-n', f'{package}/com.tarkilhk.wing.MainActivity')
        until(lambda: request()['lifecycle'] == 'resumed', 'Wing did not resume')

    def event(profile, state):
        return request('/event', json.dumps({'profile': profile, 'state': state}))

    def alert(number):
        until(lambda: notification_present(240000 + number), 'Chat notification missing')

    def stopped():
        until(lambda: not foreground(), 'Service did not stop after work ended')
        until(lambda: not notification_present(214601), 'Monitoring notification remained')
        until(lambda: not notification_present(214602), 'Monitoring summary remained')
        locks = shell('dumpsys', 'power').split('Wake Locks:', 1)[1].split('Suspend Blockers:', 1)[0]
        assert 'hermes-monitoring' not in locks, 'Wake lock leaked after work ended'

    prior_exempt = package in shell('dumpsys', 'deviceidle', 'whitelist')
    adb('forward', f'tcp:{args.port}', 'tcp:18765')
    try:
        shell('cmd', 'statusbar', 'collapse')
        shell('am', 'force-stop', package)
        shell('pm', 'grant', package, 'android.permission.POST_NOTIFICATIONS')
        shell('input', 'keyevent', 'KEYCODE_WAKEUP')
        shell('wm', 'dismiss-keyguard')
        launch()
        until(lambda: request()['ready'], 'Fixture did not establish its gateway')
        generation = request()['generation']
        stopped()
        print('PASS: idle startup has no monitoring icon or wake lock', flush=True)

        event('a', 'working')
        until(foreground, 'First chat did not start monitoring')
        connection_identity = until(
            lambda: notification_identity(214601), 'Monitoring has no group identity')
        until(lambda: notification_identity(214602) == connection_identity,
              'Monitoring summary/child differ')
        event('b', 'working')
        shell('input', 'keyevent', 'KEYCODE_HOME')
        until(lambda: request()['lifecycle'] != 'resumed', 'App stayed in foreground')
        event('a', 'waiting')
        alert(1)
        assert foreground(), 'Waiting chat stopped another working chat'
        assert connection_identity[1].endswith('g:wing_connection')
        dump = shell('dumpsys', 'notification', '--noredact')
        posted = re.search(
            rf'NotificationRecord\([^\n]*pkg={re.escape(package)}[^\n]*id=240001\b'
            r'.*?icon=Icon\([^\n]*id=([^\s)]+)', dump, re.DOTALL)
        assert posted and posted.group(1) != connection_identity[0], 'Connection/chat icons match'
        event('b', 'idle')
        alert(2)
        stopped()
        assert notification_present(240001), 'Question disappeared when monitoring stopped'
        assert notification_present(240002), 'Reply disappeared when monitoring stopped'
        print('PASS: multiple chats share monitoring; last finish stops it and retains alerts', flush=True)

        launch()
        assert not foreground(), 'Opening a waiting chat restarted monitoring'
        event('a', 'working')
        until(foreground, 'Answering the question did not restart monitoring')
        shell('input', 'keyevent', 'KEYCODE_HOME')
        event('a', 'idle')
        alert(3)
        stopped()
        print('PASS: answering resumes monitoring; final reply releases it', flush=True)

        launch()
        event('a', 'working')
        until(foreground, 'Monitoring did not restart')
        request('/close-activity', '')
        until(lambda: request()['lifecycle'] == 'detached', 'Activity was not destroyed')
        launch()
        assert request()['generation'] == generation, 'Running work lost its retained engine'
        request('/close-activity', '')
        until(lambda: request()['lifecycle'] == 'detached', 'Activity was not destroyed')
        try:
            event('a', 'waiting')
        except OSError:
            # With no Activity or working chats, Android can release this engine
            # after posting the question, before the fixture replies over HTTP.
            pass
        alert(4)
        stopped()
        assert notification_present(240004), 'Question was lost during engine release'
        launch()
        assert request()['generation'] != generation, 'Idle detached engine was not released'
        stopped()
        print('PASS: running work retains the engine; final question survives engine release', flush=True)

        shell('dumpsys', 'deviceidle', 'whitelist', f'+{package}')
        event('a', 'working')
        event('b', 'working')
        until(foreground, 'Monitoring did not start for Doze test')
        shell('input', 'keyevent', 'KEYCODE_HOME')
        shell('input', 'keyevent', 'KEYCODE_SLEEP')
        shell('dumpsys', 'battery', 'unplug')
        shell('dumpsys', 'deviceidle', 'force-idle')
        assert 'mState=IDLE' in shell('dumpsys', 'deviceidle')
        event('a', 'waiting')
        until(lambda: request()['alerts'] == 1, 'Question lost in Doze')
        assert foreground(), 'Second chat lost monitoring in Doze'
        event('b', 'idle')
        until(lambda: request()['alerts'] == 2, 'Reply lost in Doze')
        stopped()
        assert notification_present(240001) and notification_present(240002)
        print('PASS: question/reply delivery and automatic shutdown work during Doze', flush=True)

        shell('dumpsys', 'deviceidle', 'unforce')
        shell('dumpsys', 'battery', 'reset')
        shell('input', 'keyevent', 'KEYCODE_WAKEUP')
        shell('wm', 'dismiss-keyguard')
        launch()
        event('a', 'working')
        until(foreground, 'Answering did not restart monitoring')
        request('/alerts', 'false')
        stopped()
        request('/alerts', 'true')
        until(foreground, 'Enabling alerts for working chat did not restart monitoring')
        shell('input', 'keyevent', 'KEYCODE_HOME')
        event('a', 'idle')
        until(lambda: request()['alerts'] == 3, 'Final reply did not post')
        stopped()
        records = re.split(
            r'(?=^[ \t]*NotificationRecord\()',
            shell('dumpsys', 'notification', '--noredact'), flags=re.MULTILINE)
        rich = next(record for record in records if re.search(
            rf'NotificationRecord\([^\n]*pkg={re.escape(package)}[^\n]*id=240003\b', record))
        assert 'First task' in rich, 'Chat title missing'
        assert 'android.bigText' in rich and 'More readable context.' in rich, 'Expanded text missing'
        assert 'Monitoring fixture / a' in rich, 'Connection/profile missing'
        assert 'vis=PRIVATE' in rich, 'Chat content is not private on the lock screen'
        print('PASS: alert preferences and rich private notifications are preserved', flush=True)
    finally:
        shell('dumpsys', 'deviceidle', 'unforce')
        shell('dumpsys', 'battery', 'reset')
        if not prior_exempt:
            shell('dumpsys', 'deviceidle', 'whitelist', f'-{package}')
        adb('forward', '--remove', f'tcp:{args.port}')


if __name__ == '__main__':
    main()
