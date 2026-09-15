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
        ), timeout=3))

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

    def launch():
        shell('am', 'start', '-n', f'{package}/com.tarkilhk.wing.MainActivity')
        until(lambda: request()['lifecycle'] == 'resumed', 'Wing did not resume')

    def completion(expected):
        request('/event', 'idle')
        until(lambda: request()['alerts'] == expected, 'Controller did not post the completion')
        until(lambda: notification_present(240000 + expected), 'Android did not retain the alert')

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
        until(foreground, 'Monitoring service did not start')
        assert notification_present(214601), 'Ongoing monitoring notification missing'
        request('/event', 'working')
        shell('input', 'keyevent', 'KEYCODE_HOME')
        until(lambda: request()['lifecycle'] != 'resumed', 'App stayed in foreground')
        completion(1)
        print('PASS: completion posts after switching apps', flush=True)

        # Force Activity destruction while retaining the monitored Dart engine.
        launch()
        request('/event', 'working')
        request('/close-activity', '')
        until(lambda: request()['lifecycle'] == 'detached', 'Activity was not destroyed')
        completion(2)
        launch()
        assert request()['generation'] == generation, 'Activity recreation restarted the Dart engine'
        print('PASS: delivery survives Activity destruction and reopening reuses the engine', flush=True)

        # Model the explicit battery exemption granted from the settings action.
        shell('dumpsys', 'deviceidle', 'whitelist', f'+{package}')
        request('/event', 'working')
        shell('input', 'keyevent', 'KEYCODE_HOME')
        shell('input', 'keyevent', 'KEYCODE_SLEEP')
        shell('dumpsys', 'battery', 'unplug')
        shell('dumpsys', 'deviceidle', 'force-idle')
        assert 'mState=IDLE' in shell('dumpsys', 'deviceidle'), 'Device did not enter Doze'
        request('/event', 'waiting')
        until(lambda: request()['alerts'] == 3, 'Attention event was lost during Doze')
        assert notification_present(240003), 'Attention notification missing during Doze'
        completion(4)
        print('PASS: attention and completion post with the screen off in forced Doze', flush=True)

        shell('dumpsys', 'deviceidle', 'unforce')
        shell('dumpsys', 'battery', 'reset')
        shell('input', 'keyevent', 'KEYCODE_WAKEUP')
        shell('wm', 'dismiss-keyguard')
        launch()
        request('/stop', '')
        until(lambda: not foreground(), 'Monitoring service did not stop')
        assert not notification_present(214601), 'Monitoring notification remained after stop'
        locks = shell('dumpsys', 'power').split('Wake Locks:', 1)[1].split('Suspend Blockers:', 1)[0]
        assert 'hermes-monitoring' not in locks, 'Wake lock leaked after stop'
        shell('input', 'keyevent', 'KEYCODE_HOME')
        launch()
        assert not foreground(), 'Returning to Wing re-enabled stopped monitoring'
        print('PASS: disabling both alert categories releases notification/wake lock and stays off', flush=True)
        request('/start', '')
        until(foreground, 'Monitoring could not restart')
        assert notification_present(214601), 'Automatic restart has no monitoring notification'
        print('PASS: enabling alerts automatically restarts monitoring', flush=True)
    finally:
        shell('dumpsys', 'deviceidle', 'unforce')
        shell('dumpsys', 'battery', 'reset')
        if not prior_exempt:
            shell('dumpsys', 'deviceidle', 'whitelist', f'-{package}')
        adb('forward', '--remove', f'tcp:{args.port}')


if __name__ == '__main__':
    main()
