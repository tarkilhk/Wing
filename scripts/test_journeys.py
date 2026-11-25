#!/usr/bin/env python3
"""Run mandatory, deterministic Android journeys on a disposable emulator.

Without --device, create and retire an isolated API 36 AVD. Uses injected gateway
responses, real Android storage and production controls; never contacts Hermes.
The complete run ends by force-stopping Android and restoring the durable outbox.
Repeat --case for focused named-case acceptance without claiming that full gate.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack, contextmanager, nullcontext
import json
import os
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.qa import run_notification_gate as android  # noqa: E402
from scripts.test import fingerprint, stop_process_group  # noqa: E402
from scripts import test_native_process_recovery as process_recovery  # noqa: E402

CRITICAL = frozenset({
    'dark setup recovers and saves verified connection',
    'light setup recovers and saves verified connection',
    'setup saves credentials in Android secure storage and reopens them',
    'uncertain Send survives owner recreation beside a newer draft',
})
ROADMAP = frozenset({
    'current chat account usage preserves route ownership through refresh and departure',
    'Hub skill update checks keep browsing and group updates scoped',
    'teammate waits retain exact targets and stale delivery status',
    'refused turns retain their text through settlement and reopening',
    'native clarification answers from the composer with its captured generation',
    'Git review opens from chat and retains draft through held reads',
    'live tool progress and plan recovery use the production conversation',
    'drawer settings profiles chats and projects work at large text',
    'draft model slash find outputs and context use the production chat',
    'a missing staged file restores as removable without sending',
    'activity approvals and queued work keep their chat owner',
    'typed folder and website approvals retain scope and denial feedback',
    'project discovery review delivery and input jump stay native',
    'subagents goals and background work keep their chat owner',
    'completed child stays in current work while the parent streams',
    'administration checks edits and update refusal stay scoped',
    'saved answers edit regenerate branch and fork through Hermes',
})
SUITES = (
    ('critical', 'integration_test/critical_journeys_test.dart', CRITICAL),
    ('roadmap', 'integration_test/roadmap_emulator_test.dart', ROADMAP),
)


def export_journey_frames(device: str, package: str, log_path: Path,
                          output: Path, evidence: dict, *, require_frames=False):
    """Export declared Flutter frames before the caller retires its owned app."""
    evidence['frames'] = []
    try:
        paths = sorted(set(re.findall(r'Journey frame: ([^"\\\s]+\.png)', log_path.read_text())))
        if require_frames and not paths:
            raise RuntimeError('Capture requested but no Journey frames were recorded')
        for path in paths:
            try:
                output.mkdir(parents=True, exist_ok=True)
                destination = output / Path(path).name
                with destination.open('wb') as frame:
                    subprocess.run([android.adb_path(), '-s', device, 'exec-out',
                                    'run-as', package, 'cat', path],
                                   stdout=frame, check=True, timeout=25)
                evidence['frames'].append(str(destination))
            except (OSError, subprocess.SubprocessError) as error:
                evidence.setdefault('capture_errors', []).append(str(error))
                evidence['passed'] = False
    except (OSError, RuntimeError) as error:
        evidence.setdefault('capture_errors', []).append(str(error))
        evidence['passed'] = False


def journey_environment():
    return {**os.environ,
            'ORG_GRADLE_PROJECT_notificationQa': 'true',
            'ORG_GRADLE_PROJECT_performanceQa': 'false',
            'ORG_GRADLE_PROJECT_nativeShareQa': 'false',
            'ORG_GRADLE_PROJECT_wingDevelopment': 'false'}


def prepare_roadmap(device: str, target: str, output: Path, evidence: dict):
    """Install the owned QA package before granting roadmap prerequisites."""
    commands = (
        ('build', ['flutter', 'build', 'apk', '--debug', '--no-pub',
                   '--target-platform', 'android-x64', '-t', target]),
        ('install', [android.adb_path(), '-s', device, 'install',
                     '--no-incremental', '-r',
                     str(ROOT / 'build/app/outputs/flutter-apk/app-debug.apk')]),
    )
    for name, command in commands:
        step = evidence[name] = {'passed': False, 'command': command}
        with (output / f'prepare-roadmap-{name}.log').open('w') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True,
                                       env=journey_environment())
            try:
                step['exit_code'] = process.wait(timeout=900 if name == 'build' else 180)
                step['passed'] = step['exit_code'] == 0
                if not step['passed']:
                    raise RuntimeError('Roadmap preparation ' + name + ' failed')
            finally:
                stop_process_group(process)


def verdict(lines: list[str], returncode: int, expected: frozenset[str]) -> dict:
    """Only completed, non-skipped named journeys constitute acceptance."""
    names = {}
    completed = []
    skipped = []
    failures = []
    done = False
    summaries = 0
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue  # Flutter build/install diagnostics are not test events.
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        if kind == 'testStart':
            names[event['test']['id']] = event['test']['name']
        elif kind == 'testDone' and not event.get('hidden'):
            name = names.get(event.get('testID'), '<unregistered test>')
            if event.get('skipped'):
                skipped.append(name)
            elif event.get('result') == 'success':
                completed.append(name)
            else:
                failures.append(name)
        elif kind == 'error':
            failures.append(names.get(event.get('testID'), '<test loading>'))
        elif kind == 'done':
            summaries += 1
            done = event.get('success') is True
    missing = sorted(expected.difference(completed))
    unexpected = sorted(set(completed).difference(expected))
    duplicates = sorted(name for name in expected if completed.count(name) > 1)
    passed = (bool(expected) and returncode == 0 and summaries == 1 and done
              and not (missing or unexpected or duplicates or skipped or failures))
    return {'passed': passed, 'completed': completed, 'skipped': skipped,
            'failed': failures, 'missing': missing, 'unexpected': unexpected, 'duplicates': duplicates,
            'process_exit': returncode, 'test_run_completed': done, 'summary_count': summaries}



@contextmanager
def completed_onboarding(device: str, evidence: dict):
    """Scope established permission/battery prerequisites to the owned QA app."""
    package = 'com.tarkilhk.wing.notificationqa'
    def shell(*args):
        return android.device(device, 'shell', *args)
    if not shell('pm', 'path', package).strip().startswith('package:'):
        raise RuntimeError('Critical journey did not leave the owned QA package installed')
    state = shell('dumpsys', 'package', package)
    permissions = {
        permission: bool(re.search(re.escape(permission) + r': granted=true', state))
        for permission in ('android.permission.POST_NOTIFICATIONS', 'android.permission.RECORD_AUDIO')
    }
    exempt = package in shell('dumpsys', 'deviceidle', 'whitelist')
    evidence.update(package=package, permissions_before=permissions, battery_exempt_before=exempt,
                    scope='completed onboarding; permission prompts and default battery policy are separate acceptance')
    with ExitStack() as cleanup:
        if not exempt:
            cleanup.callback(shell, 'dumpsys', 'deviceidle', 'whitelist', '-' + package)
            shell('dumpsys', 'deviceidle', 'whitelist', '+' + package)
        for permission, granted in permissions.items():
            if not granted:
                cleanup.callback(shell, 'pm', 'revoke', package, permission)
                shell('pm', 'grant', package, permission)
        cleanup.callback(shell, 'am', 'force-stop', package)
        shell('am', 'force-stop', package)
        yield
    evidence['restored'] = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Reuse a disposable emulator; physical devices are rejected')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/android-journeys')
    parser.add_argument('--capture-frames', action='store_true',
                        help='Export production Flutter frames from journey capture points before retiring the emulator')
    parser.add_argument('--case', action='append',
                        help='Exact registered critical or roadmap case; repeat for focused acceptance')
    args = parser.parse_args()
    selected = frozenset(args.case) if args.case else CRITICAL | ROADMAP
    if not selected <= CRITICAL | ROADMAP:
        parser.error('--case must name an exact registered critical or roadmap case')
    suites = [(name, target, expected & selected) for name, target, expected in SUITES
              if expected & selected]
    os.chdir(ROOT)
    if args.device and not args.device.startswith('emulator-'):
        parser.error('Android journeys require a disposable emulator')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    android.OUTPUT = output
    before = fingerprint()
    result = {'passed': False, 'scope': 'focused' if args.case else 'full',
              'selected_cases': sorted(selected), 'source_before': before, 'suites': {}}
    try:
        with nullcontext(args.device) if args.device else android.owned_emulator() as device:
            android.require_emulator(device)
            android.device(device, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
            android.device(device, 'shell', 'wm', 'dismiss-keyguard')
            result['device'] = device
            if suites[0][0] == 'roadmap':
                prepare_roadmap(device, suites[0][1], output,
                                result.setdefault('preparation', {}))
            for name, target, expected in suites:
                command = ['flutter', 'test', '--no-pub', '--no-uninstall', '-d', device,
                           '--reporter=json', target]
                if args.case:
                    command.extend(['--name', '^(?:' + '|'.join(
                        re.escape(case) for case in sorted(expected)) + ')$'])
                if args.capture_frames:
                    command.append('--dart-define=CAPTURE_JOURNEYS=true')
                suite = result['suites'][name] = {'passed': False, 'command': command}
                log_path = output / f'{name}.jsonl'
                setup = completed_onboarding(device, suite.setdefault('onboarding', {})) if name == 'roadmap' else nullcontext()
                with setup, log_path.open('w') as log:
                    process = subprocess.Popen(command, cwd=ROOT, stdout=log,
                                               stderr=subprocess.STDOUT, start_new_session=True,
                                               env=journey_environment())
                    try:
                        code = process.wait(timeout=900)
                        log.flush()
                        suite.update(verdict(log_path.read_text().splitlines(), code, expected))
                    except (OSError, subprocess.SubprocessError) as error:
                        suite['error'] = str(error)
                        raise
                    finally:
                        # Capture before force-stop/onboarding cleanup and AVD retirement.
                        try:
                            if not suite['passed']:
                                android.capture_failure(device, output / (name + '-failure'))
                        except Exception as error:
                            suite.setdefault('capture_errors', []).append(str(error))
                        finally:
                            stop_process_group(process)
                    export_journey_frames(device, 'com.tarkilhk.wing.notificationqa',
                                          log_path, output / (name + '-frames'), suite)
                if not suite['passed']:
                    break
            else:
                if args.case:
                    result['passed'] = True
                else:
                    result['process_recovery'] = process_recovery.run(device, output / 'process-recovery')
                    result['passed'] = result['process_recovery'].get('passed') is True
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        result.update(passed=False, error=str(error))
    finally:
        result['source_after'] = fingerprint()
        if result['source_after'] != before:
            result.update(passed=False, source_changed=True)
        (output / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    if not result['passed']:
        for log in output.glob('*.jsonl'):
            print(f'{log.name}:\n{log.read_text()[-16000:]}', file=sys.stderr)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
