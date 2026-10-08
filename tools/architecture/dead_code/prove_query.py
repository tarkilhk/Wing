#!/usr/bin/env python3
"""Bounded semantic-query contract proof; never changes application source."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiled', type=Path)
    parser.add_argument('--evidence-dir', type=Path)
    args = parser.parse_args()
    if args.compiled is not None and not args.compiled.is_file():
        parser.error('--compiled requires an existing executable')
    app = Path(__file__).resolve().parents[3]
    sdk = app.parent / '.toolchain/flutter/bin/cache/dart-sdk/bin/dart'
    query = Path(__file__).with_name('resolved_callers.dart')
    fixture = json.loads(Path(__file__).with_name('query_contract.fixture.json').read_text())
    evidence = args.evidence_dir
    if evidence is not None:
        evidence.mkdir(parents=True, exist_ok=True)
        inputs = [query, Path(__file__).with_name('query_contract.fixture.json'),
                  Path(__file__), app / 'tools/architecture/dart_sdk.dart']
        if args.compiled is not None:
            inputs.append(args.compiled)
        (evidence / 'inputs.json').write_text(json.dumps({
            str(path.resolve()): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in inputs
        }, indent=2) + '\n')

    def record(mode, case, command, result, output=None):
        if evidence is None:
            return
        (evidence / f'{mode}-{case}.json').write_text(json.dumps({
            'command': command, 'exit': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr,
            'inventory': json.loads(output.read_text())
                         if output is not None and output.exists() else None,
        }, indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='wing-resolved-query-') as temp:
        root = Path(temp)
        subprocess.run(['git', 'init', '-q', root], check=True)
        for name, contents in fixture['files'].items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        config = root / '.dart_tool/package_config.json'
        config.parent.mkdir()
        config.write_text(json.dumps({'configVersion': 2, 'packages': [{
            'name': 'fixture', 'rootUri': '../', 'packageUri': 'lib/',
            'languageVersion': '3.12',
        }]}))
        manifest = root / 'targets.json'
        manifest.write_text(json.dumps(fixture['targets']))
        # A removed tracked path stays in Git's index until staged. Census the
        # physical worktree while semantic imports still fail if they need it.
        removed = root / 'lib/removed.dart'
        removed.write_text('class Removed {}\n')
        subprocess.run(['git', '-C', str(root), 'add', 'lib/removed.dart'], check=True)
        removed.unlink()
        output = root / 'proof.json'
        source = [str(sdk), '--packages=' + str(app / '.dart_tool/package_config.json'),
                  str(query)]
        sdk_path = str(sdk.parent.parent)
        executables = [('source', source)]
        if args.compiled is not None:
            executables.append(('compiled', [str(args.compiled.resolve())]))
        for mode, executable in executables:
            command = [*executable, str(root), str(manifest), str(output), '--sdk', sdk_path]
            valid = subprocess.run(command, capture_output=True, text=True)
            record(mode, 'valid', command, valid, output)
            assert valid.returncode == 0, valid.stdout + valid.stderr
            proof = json.loads(output.read_text())
            refs = [r for r in proof['references'] if r['target'] == 'RETIRED']
            assert {r['caller'] for r in refs} == set(fixture['expected_resolved_callers']), refs
            assert len(refs) == 4, refs  # cascade, tear-off, extension, part
            assert all(r['symbol'] == 'Transport.retired' for r in refs)
            assert all(r['caller'] != 'Other.retired' for r in refs)
            constructor_refs = [r for r in proof['references'] if r['target'] != 'RETIRED']
            keys = ('target', 'file', 'line', 'caller')
            observed = sorted(tuple(r[k] for k in keys) for r in constructor_refs)
            expected = sorted(tuple(r[k] for k in keys)
                              for r in fixture['expected_constructor_references'])
            assert observed == expected, constructor_refs
            for ref in constructor_refs:
                declaration = fixture['expected_constructor_declarations'][ref['target']]
                assert {key: ref[key] for key in declaration} == declaration, ref
                assert ref['file'] != 'lib/constructor_calls.dart' or ref['line'] < 14, ref
            assert len(constructor_refs) == 10, constructor_refs
            assert {r['caller'] for r in proof['unresolved_candidate_spellings']} == set(
                fixture['expected_unresolved_callers'])
            assert not proof['resolution_failures']
            assert 'lib/removed.dart' not in proof['authored_units']
            assert proof['analysis_sdk_path'] == sdk_path
            assert proof['analysis_sdk_version'] == (sdk.parent.parent / 'version').read_text().strip()
            print(f'PASS {mode}: four actual canonical references; unrelated symbol excluded')
            print(f'PASS {mode}: ten named/unnamed constructor occurrences and exact declaration locations')
            print(f'PASS {mode}: prefixed/aliased/conditional barrel/part calls, tear-offs, explicit super/redirect')
            print(f'PASS {mode}: dynamic obligation, deleted tracked path and exact SDK provenance')

            # A failed resolver may never establish a zero-reference proof.
            broken_path = root / 'lib/broken.dart'
            broken_path.write_text('void broken() { Missing(); }\n')
            output.unlink()
            invalid = subprocess.run(command, capture_output=True, text=True)
            record(mode, 'semantic-input', command, invalid, output)
            assert invalid.returncode == 2, invalid.stdout + invalid.stderr
            broken = json.loads(next(line for line in invalid.stderr.splitlines()
                                     if line.startswith('{"resolution_failures":')))
            assert any(e['file'] == 'lib/broken.dart' for e in broken['resolution_failures'])
            assert not output.exists(), 'Malformed semantics may not publish a proof'
            broken_path.unlink()
            print(f'PASS {mode}: malformed semantics exit2 with diagnostic and no proof')

            invalid_sdk_command = [*executable, str(root), str(manifest), str(output),
                                   '--sdk', str(root / 'invalid-sdk')]
            invalid_sdk = subprocess.run(invalid_sdk_command, capture_output=True, text=True)
            record(mode, 'sdk-input', invalid_sdk_command, invalid_sdk, output)
            assert invalid_sdk.returncode == 2, invalid_sdk.stdout + invalid_sdk.stderr
            assert '[RESOLVED_CALLERS INPUT]' in invalid_sdk.stderr
            assert not output.exists(), 'An invalid SDK may not publish a proof'
            print(f'PASS {mode}: invalid SDK exits2 and cannot publish proof')

            malformed_manifest = root / 'invalid-targets.json'
            malformed_manifest.write_text('{"targets":"invalid"}')
            malformed_command = [*executable, str(root), str(malformed_manifest),
                                 str(output), '--sdk', sdk_path]
            malformed = subprocess.run(malformed_command, capture_output=True, text=True)
            record(mode, 'manifest-input', malformed_command, malformed, output)
            assert malformed.returncode == 2, malformed.stdout + malformed.stderr
            assert '[RESOLVED_CALLERS INPUT]' in malformed.stderr
            assert not output.exists(), 'Malformed targets may not publish a proof'
            print(f'PASS {mode}: malformed targets exit2 and cannot publish proof')


if __name__ == '__main__':
    main()
