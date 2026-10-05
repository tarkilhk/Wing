#!/usr/bin/env python3
"""Prove actual standalone parsed-Kotlin CLI bad1/valid0/input2 contracts."""
import json
from pathlib import Path
import subprocess
import tempfile
from file_api_boundary import command
from permission_lifecycle import lifecycle_command, ID as PERMISSION_ID


def main():
    fixtures = json.loads(Path(__file__).with_name('contract.fixture.json').read_text())['cases']
    run = command()
    for fixture in fixtures:
        with tempfile.TemporaryDirectory(prefix='wing-voice-guard-') as scratch:
            source = Path(scratch) / 'VoiceCapture.kt'
            source.write_text(fixture['source'])
            result = subprocess.run(run + [str(source)], capture_output=True, text=True)
            assert result.returncode == fixture['exit'], (fixture['name'], result.stdout, result.stderr)
            if fixture['exit'] == 1:
                assert f":{fixture['line']} [NATIVE_VOICE_FILE_API_BOUNDARY]" in result.stdout, (fixture['name'], result.stdout)
            if fixture['exit'] == 2:
                assert '[NATIVE_VOICE_FILE_API_BOUNDARY]' in result.stderr
    print(f'NATIVE_VOICE_FILE_API_BOUNDARY: {len(fixtures)} actual CLI exits proved (1/0/2)')
    lifecycle = json.loads(Path(__file__).with_name('permission_lifecycle.fixture.json').read_text())['cases']
    run = lifecycle_command()
    for fixture in lifecycle:
        with tempfile.TemporaryDirectory(prefix='wing-voice-permission-guard-') as scratch:
            sources = []
            for name, text in fixture['sources'].items():
                source = Path(scratch) / name
                source.write_text(text)
                sources.append(str(source))
            result = subprocess.run(run + sources, capture_output=True, text=True)
            assert result.returncode == fixture['exit'], (fixture['name'], result.stdout, result.stderr)
            if fixture['exit'] == 1:
                assert f":{fixture['line']} [{PERMISSION_ID}]" in result.stdout, (fixture['name'], result.stdout)
            if fixture['exit'] == 2:
                assert f'[{PERMISSION_ID}]' in result.stderr
    print(f'{PERMISSION_ID}: {len(lifecycle)} actual CLI exits proved (1/0/2)')



if __name__ == '__main__':
    main()
