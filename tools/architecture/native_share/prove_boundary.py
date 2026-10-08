#!/usr/bin/env python3
"""Actual standalone Kotlin PSI CLI exit proofs on raw synthetic artifacts."""
import json
from pathlib import Path
import subprocess
import tempfile
from provider_boundary import command


def main():
    cases = json.loads(Path(__file__).with_name('contract.fixture.json').read_text())['cases']
    run = command()
    for case in cases:
        with tempfile.TemporaryDirectory(prefix='wing-provider-boundary-') as scratch:
            path = Path(scratch) / 'MainActivity.kt'
            path.write_text(case['code'])
            rule = 'bounded-queues' if case.get('id') == 'NATIVE_SHARE_BOUNDED_QUEUE' else 'provider-boundary'
            result = subprocess.run(run + ['--rule=' + rule, str(path)], text=True, capture_output=True)
            assert result.returncode == case['exit'], (case['name'], result.stdout, result.stderr)
            if case['exit']:
                assert case.get('id', 'NATIVE_SHARE_PROVIDER_BOUNDARY') in result.stdout + result.stderr
            if case['exit'] == 1:
                assert ':' + str(case.get('line', 1)) + ' [' + case.get('id', 'NATIVE_SHARE_PROVIDER_BOUNDARY') + ']' in result.stdout
    from prove_qa_isolation import main as prove_qa_isolation
    prove_qa_isolation()
    print(f'NATIVE_SHARE_PROVIDER_BOUNDARY: {len(cases)} CLI fixture exits proved (1/0/2)')


if __name__ == '__main__':
    main()
