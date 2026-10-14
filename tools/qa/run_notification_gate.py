#!/usr/bin/env python3
"""Build and run the real shade-tap regression on an isolated API36 emulator.

With no serial, own an ephemeral AVD (SDK image must already be installed).
--serial reuses an operator-owned emulator; only the notification QA app is reset.
"""
import argparse
from contextlib import contextmanager
import os
from pathlib import Path
import subprocess
import sys
import time

IMAGE = 'system-images;android-36;google_apis;x86_64'
OUTPUT = Path('build/notification-gate')


def command(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=600, **kwargs)


def device(serial, *args):
    return subprocess.check_output(
        ['adb', '-s', serial, *args], text=True, timeout=25,
        stderr=subprocess.PIPE).strip()


def require_emulator(serial):
    if not serial.startswith('emulator-') or device(serial, 'shell', 'getprop', 'ro.kernel.qemu') != '1':
        raise ValueError('Notification gate requires a disposable Android emulator')


def check_on_emulator(serial):
    require_emulator(serial)
    # Fresh SDK AVDs start behind the keyguard. The fixture awaits its first
    # frame, and the real shade gesture requires an unlocked display.
    device(serial, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    device(serial, 'shell', 'wm', 'dismiss-keyguard')
    command('adb', '-s', serial, 'install', '--no-incremental', '-r', '-g',
            'build/app/outputs/flutter-apk/app-debug.apk')
    try:
        command(sys.executable, 'tools/qa/check_notification_revamp.py',
                '--serial', serial, '--output', str(OUTPUT), '--tap-only')
    except subprocess.CalledProcessError:
        for name, args in [
            ('app.log', ('logcat', '-d', '-t', '500', '-s',
                         'flutter:V', 'AndroidRuntime:E', 'ActivityTaskManager:I')),
            ('activity.txt', ('shell', 'dumpsys', 'activity', 'activities')),
        ]:
            try:
                (OUTPUT / name).write_text(device(serial, *args))
            except (OSError, subprocess.SubprocessError):
                pass
        raise


@contextmanager
def owned_emulator():
    sdk = Path(os.environ['ANDROID_HOME'])
    serial = 'emulator-5562'
    connected = subprocess.check_output(['adb', 'devices'], text=True, timeout=25)
    if any(line.split()[0] == serial for line in connected.splitlines()[1:] if line.split()):
        raise ValueError(f'{serial} is occupied; refusing to replace another emulator')
    avds = OUTPUT.resolve() / 'avd'
    avds.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, 'ANDROID_AVD_HOME': str(avds)}
    command(str(sdk / 'cmdline-tools/latest/bin/avdmanager'), 'create', 'avd',
            '--force', '--name', 'wing_notification_gate', '--package', IMAGE,
            '--device', 'pixel_2', input='no\n', text=True, env=env)
    with (OUTPUT / 'emulator.log').open('w') as log:
        process = subprocess.Popen([
            str(sdk / 'emulator/emulator'), '-avd', 'wing_notification_gate',
            '-port', '5562', '-no-window', '-no-audio', '-no-boot-anim',
            '-no-snapshot', '-gpu', 'swiftshader', '-feature', '-Vulkan',
            '-memory', '2048', '-cores', '2', '-skin', '720x1280',
            '-no-metrics', '-show-kernel',
        ], stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f'Emulator exited; see {OUTPUT}/emulator.log')
                try:
                    if device(serial, 'shell', 'getprop', 'sys.boot_completed') == '1':
                        break
                except subprocess.CalledProcessError:
                    pass
                time.sleep(1)
            else:
                raise TimeoutError('Notification emulator did not boot within 300 seconds')
            yield serial
        finally:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', help='Reuse this disposable emulator instead of starting an AVD')
    args = parser.parse_args()
    if args.serial:
        require_emulator(args.serial)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Build before booting the owned AVD to keep CI memory pressure bounded.
    command('flutter', 'build', 'apk', '--debug', '--no-pub',
            '--target-platform', 'android-x64', '-t',
            'integration_test/notification_revamp_device.dart',
            env={**os.environ, 'ORG_GRADLE_PROJECT_notificationQa': 'true'})
    if args.serial:
        check_on_emulator(args.serial)
    else:
        with owned_emulator() as serial:
            check_on_emulator(serial)


if __name__ == '__main__':
    main()
