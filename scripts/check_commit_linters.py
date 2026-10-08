#!/usr/bin/env python3
"""Run existing Wing source linters, optionally against exactly the staged tree.

Dart entry points share one VM startup. Individual rule logic stays unchanged.
No app tests, Gradle builds, network access or automatic source edits run here.
"""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


PYTHON_GUARDS = (
    'tools/architecture/rules/authored_census.py',
    'tools/architecture/rules/native_retired_resources.py',
    'tools/architecture/rules/fixture_model_catalog.py',
    'tools/architecture/rules/retired_fixture_recovery.py',
    'tools/architecture/native_share/provider_boundary.py',
    'tools/architecture/native_notification/retired_action.py',
    'tools/architecture/native_notification/retired_declaration.py',
    'tools/architecture/native_voice/file_api_boundary.py',
    'tools/architecture/native_voice/permission_lifecycle.py',
)
NATIVE_CACHES = (
    'native-share-guard', 'native-notification-action-guard',
    'native-retired-declaration-guard', 'native-voice-guard',
    'native-voice-permission-guard',
)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


@contextmanager
def checkout(root, staged):
    if not staged:
        yield root
        return
    tree = git(root, 'write-tree')
    # Git may export an alternate index for path-limited commits. Capture that
    # tree above, then give the isolated checkout its own Git environment.
    local_names = git(root, 'rev-parse', '--local-env-vars').splitlines()
    saved = {name: os.environ.pop(name) for name in local_names if name in os.environ}
    try:
        with staged_checkout(root, tree) as target:
            yield target
    finally:
        os.environ.update(saved)


@contextmanager
def staged_checkout(root, tree):
    with tempfile.TemporaryDirectory(prefix='wing-staged-linters-') as directory:
        target = Path(directory) / 'source'
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout',
                        str(root), str(target)], check=True)
        subprocess.run(['git', '-C', str(target), 'read-tree', tree], check=True)
        subprocess.run(['git', '-C', str(target), 'checkout-index', '--all'], check=True)
        config = root / '.dart_tool/package_config.json'
        if not config.is_file():
            raise ValueError('Run flutter pub get before committing.')
        (target / '.dart_tool').mkdir()
        shutil.copy2(config, target / '.dart_tool/package_config.json')
        # Existing native compile caches bind source/jar hashes and JDK identity.
        # Sharing only these ignored caches avoids recompiling unchanged guards.
        (target / 'build').mkdir()
        for name in NATIVE_CACHES:
            cache = root / 'build' / name
            cache.mkdir(parents=True, exist_ok=True)
            (target / 'build' / name).symlink_to(cache, target_is_directory=True)
        yield target


def dart_driver(root, destination):
    aggregate = root / 'tools/architecture/check_all.dart'
    covered = {
        (aggregate.parent / path).resolve()
        for path in re.findall(r"import '([^']+)' as \w+;", aggregate.read_text())
    }
    commands = [('architecture', aggregate)]
    commands.extend((path.stem, path) for path in sorted(
        (root / 'tools/architecture/rules').glob('*.dart'))
        if path.resolve() not in covered)
    imports = ["import 'dart:io';",
               f"import '{(aggregate.parent / 'cli.dart').as_uri()}' as cli;",
               f"import '{(aggregate.parent / 'model.dart').as_uri()}' as model;",
               f"import '{(aggregate.parent / 'semantic_context.dart').as_uri()}' as semantic;"]
    callbacks = []
    for index, (name, path) in enumerate(commands):
        source = path.read_text()
        signature = re.search(r'\b(Future<void>|void)\s+main\s*\(List<String>\s+\w+\)', source)
        if not signature:
            raise ValueError(f'{path.relative_to(root)}: unsupported linter entry point.')
        imports.append(f"import '{path.as_uri()}' as rule{index};")
        if signature.group(1) == 'void' and re.search(
                r'void\s+main\(List<String>\s+(\w+)\)\s*=>\s*run\(\1,\s*\{id:\s*check\}\);', source):
            # These existing standalone CLI wrappers intentionally return void.
            # Await their shared runner directly so asynchronous findings settle.
            call = f'await cli.run(const <String>[], {{rule{index}.id: rule{index}.check}});'
        else:
            if signature.group(1) == 'void' and re.search(
                    r'void\s+main\([^)]*\)\s*=>\s*run\(', source):
                raise ValueError(f'{path.relative_to(root)}: unsupported asynchronous CLI wrapper.')
            await_call = 'await ' if signature.group(1).startswith('Future') else ''
            call = f'{await_call}rule{index}.main(const <String>[]);'
        callbacks.append(f"('{name}', () async {{ {call} }})")
    destination.write_text('\n'.join(imports) + '''
Future<void> main() async {
  await model.withSharedSourceParses(() => semantic.withSharedAnalysisSummaries(() async {
  for (final entry in <(String, Future<void> Function())>[
''' + ',\n'.join(callbacks) + '''
  ]) {
    exitCode = 0;
    await entry.$2();
    if (exitCode != 0) {
      stderr.writeln('Wing commit lint failed: ${entry.$1}');
      return;
    }
  }
  exitCode = 0;
  }));
}
''')
    return len(commands)


def checked(command, root):
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    if result.returncode:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true',
                        help='Check the Git index in an isolated checkout')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        dart = shutil.which('dart')
        if not dart:
            raise ValueError('Dart is missing; activate your Flutter toolchain or install hooks with --toolchain-env.')
        if Path(git(root, 'rev-parse', '--show-toplevel')).resolve() != root:
            raise ValueError('The runner must belong to the actual checkout.')
        print('Checking Wing staged linters...' if args.staged else 'Checking Wing source linters...', flush=True)
        with checkout(root, args.staged) as source:
            baseline = json.loads((source / 'tools/architecture/baseline.json').read_text())
            if baseline != {'schema': 1, 'entries': []}:
                raise ValueError('Architecture baseline must remain empty.')
            config = source / '.dart_tool/package_config.json'
            if not config.is_file():
                raise ValueError('Run flutter pub get before checking linters.')
            with tempfile.TemporaryDirectory(prefix='wing-lint-driver-') as directory:
                driver = Path(directory) / 'check.dart'
                count = dart_driver(source, driver)
                result = checked([dart, f'--packages={config}', str(driver)], source)
                if result:
                    return result
                for guard in PYTHON_GUARDS:
                    result = checked([sys.executable, guard], source)
                    if result:
                        return result
        print(f'Wing linters passed: {count} Dart commands and {len(PYTHON_GUARDS)} Python/native checks.')
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'[WING_COMMIT_LINT_INPUT] {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
