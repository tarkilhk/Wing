#!/usr/bin/env python3
"""Exercise five real Chats refreshes through the benchmark-only service hook."""
import argparse
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from wing_perf_client import WingPerfClient

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
report = {'refreshes': []}

def save():
    args.output.write_text(json.dumps(report, indent=2) + '\n')

with WingPerfClient(args.serial) as client:
    for run in range(1, 6):
        result = client.action('refresh')
        result['run'] = run
        result['passed'] = (result['initialized'] and not result['loading']
                            and not result['controllerError']
                            and result['visibleErrors'] == 0
                            and result['connection'] == 'Connected')
        report['refreshes'].append(result)
        save()
        print(f"Refresh {run}: {result['elapsedMs']} ms, passed={result['passed']}", flush=True)
        if not result['passed']:
            raise SystemExit('Refresh acceptance failed; evidence saved')
    client.call('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(5)
    client.call('shell', 'am', 'start', '-n',
                'com.tarkilhk.wing.dev/com.tarkilhk.wing.MainActivity')
    start = time.monotonic()
    while time.monotonic() - start < 30:
        try:
            result = client.action('snapshot')
            if (result['initialized'] and result['connection'] == 'Connected'
                    and not result['loading'] and not result['controllerError']
                    and result['visibleErrors'] == 0):
                break
        except RuntimeError:
            result = {'connection': 'unavailable'}
        time.sleep(1)
    report['resume'] = result
    report['resume']['confirmedReadyMs'] = round((time.monotonic() - start) * 1000)
    save()
    if (not result.get('initialized') or result.get('connection') != 'Connected'
            or result.get('loading', True) or result.get('controllerError', True)
            or result.get('visibleErrors', 1)):
        raise SystemExit('Resume acceptance failed; evidence saved')
    print('Resume: connected with no visible errors', flush=True)

# Additional coverage after the primary timing runs. Opening/closing filters
# changes no selections. Expanding a group changes only this screen's local state.
with WingPerfClient(args.serial) as client:
    def ui_nodes():
        path = '/data/local/tmp/wing-performance-ui.xml'
        try:
            client.call('shell', 'uiautomator', 'dump', path)
            xml = client.call('shell', 'cat', path)
            return list(ET.fromstring(xml).iter('node'))
        finally:
            client.call('shell', 'rm', '-f', path)

    def label(node):
        return node.attrib.get('content-desc') or node.attrib.get('text', '')

    def tap(node):
        bounds = list(map(int, re.findall(r'\d+', node.attrib['bounds'])))
        client.call('shell', 'input', 'tap', str((bounds[0] + bounds[2]) // 2),
                    str((bounds[1] + bounds[3]) // 2))

    report['menus'] = {}
    for name in ['Status', 'Profile', 'Project']:
        client.action('top')
        matches = [n for n in ui_nodes() if label(n).startswith(name + ' filter,')]
        if len(matches) != 1:
            report['menus'][name] = 'control unavailable to UI automation'
            save()
            continue
        tap(matches[0])
        close = [n for n in ui_nodes() if label(n) == 'Close ' + name]
        if len(close) != 1:
            report['menus'][name] = 'open not confirmed'
            save()
            raise SystemExit('Filter popup could not be verified; evidence saved')
        tap(close[0])
        report['menus'][name] = 'opened and closed without changing selection'
        save()
    client.action('top')
    groups = []
    for node in ui_nodes():
        match = re.fullmatch(r'Show all (\d+) chats', label(node))
        if match:
            groups.append((int(match[1]), node))
    if groups:
        count, node = max(groups, key=lambda item: item[0])
        tap(node)
        time.sleep(1)
        client.action('snapshot')  # Verify the tap kept the Chats screen open.
        expanded_path = args.output.with_name('expanded-group.json')
        outcome = subprocess.run([
            sys.executable, 'tools/qa/measure_chat_scrolling.py', '--serial', args.serial,
            '--runs', '1', '--label', f'candidate-expanded-{count}-chats',
            '--output', str(expanded_path),
        ], timeout=100, capture_output=True, text=True)
        report['expandedGroup'] = {'chats': count, 'exitCode': outcome.returncode}
        save()
        if outcome.returncode:
            raise SystemExit('Expanded group measurement failed; evidence saved')
        print(f'Expanded group: measured {count} chats', flush=True)
    else:
        report['expandedGroup'] = {'skipped': 'No expansion button visible at the top'}
        save()
