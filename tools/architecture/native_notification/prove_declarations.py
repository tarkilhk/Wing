#!/usr/bin/env python3
"""Exercise the independent retired-declaration CLI's finite 0/1/2 contract."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from retired_declaration import ID, NATIVE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-dir', type=Path)
    args = parser.parse_args()
    cases = json.loads(Path(__file__).with_name('declaration.fixture.json').read_text())['cases']
    runner = [sys.executable, str(Path(__file__).with_name('retired_declaration.py'))]
    if args.cache_dir:
        runner += ['--cache-dir', str(args.cache_dir)]
    for case in cases:
        with tempfile.TemporaryDirectory(prefix='wing-native-declaration-') as scratch:
            root = Path(scratch)
            for name, source in case['files'].items():
                path = root / NATIVE / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            result = subprocess.run(runner + ['--root', str(root)], capture_output=True, text=True)
            assert result.returncode == case['exit'], (case['name'], result.returncode, result.stderr)
            diagnostic = f'[{ID}]'
            if case['exit'] == 2:
                assert diagnostic in result.stderr, case['name']
                assert diagnostic not in result.stdout, case['name']
            else:
                assert result.stdout.count(diagnostic) == len(case['findings']), case['name']
                for file, line, symbol in case['findings']:
                    assert f'/{file}:{line} {diagnostic} Retire {symbol};' in result.stdout, case['name']
    print(f'{ID}: {len(cases)} standalone CLI fixtures passed (0/1/2)')


if __name__ == '__main__':
    main()
