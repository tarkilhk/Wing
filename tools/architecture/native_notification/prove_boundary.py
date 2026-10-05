#!/usr/bin/env python3
"""Prove exact standalone parsed-Kotlin notification action CLI exits 0/1/2."""
import json
from pathlib import Path
import subprocess
import tempfile
from retired_action import command, ID


def main():
    cases = json.loads(Path(__file__).with_name('contract.fixture.json').read_text())['cases']
    run = command()
    for case in cases:
        with tempfile.TemporaryDirectory(prefix='wing-notification-action-') as scratch:
            path = Path(scratch) / 'ChatNotifications.kt'
            path.write_text(case['source'])
            result = subprocess.run(run + [str(path)], capture_output=True, text=True)
            assert result.returncode == case['exit'], (case['name'], result.returncode)
            diagnostic = f'[{ID}]'
            if case['exit'] == 2:
                assert diagnostic in result.stderr
            else:
                assert result.stdout.count(diagnostic) == case['count'], case['name']
                if case['exit'] == 1:
                    assert f":{case['line']} {diagnostic}" in result.stdout, case['name']
    print(f'{ID}: {len(cases)} actual CLI fixtures passed (0/1/2)')


if __name__ == '__main__':
    main()
