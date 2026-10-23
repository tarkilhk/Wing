import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys
from unittest.mock import patch

from scripts import install_android_sdk as installer


class SdkInstall(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.sdk = self.root / 'sdk'
        self.output = self.root / 'diagnostics'
        manager = self.sdk / 'cmdline-tools/latest/bin/sdkmanager'
        manager.parent.mkdir(parents=True)
        manager.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
root = Path(os.environ['ANDROID_HOME'])
counter = root / 'calls'
attempt = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(attempt))
assert sys.argv[1:] == ['--verbose', 'emulator', 'system-images;android-36;google_apis;x86_64']
print('SDK download attempt', attempt)
if attempt <= int(os.environ['FAKE_SDK_FAILURES']):
    archive = root / '.temp/PackageOperation01/emulator.zip'
    archive.parent.mkdir(parents=True, exist_ok=True)
    archive.write_bytes(b'PK truncated')
    print('Error on ZipFile unknown archive', file=sys.stderr)
    sys.exit(7)
''')
        manager.chmod(0o755)

    def install(self, failures):
        with patch.dict(os.environ, {'ANDROID_HOME': str(self.sdk),
                                    'FAKE_SDK_FAILURES': str(failures)}), \
             patch.object(installer.time, 'sleep') as sleep, \
             contextlib.redirect_stdout(io.StringIO()):
            code = installer.install(
                ['emulator', 'system-images;android-36;google_apis;x86_64'],
                self.output,
            )
        return code, sleep

    def test_transient_archive_failures_recover_and_keep_each_attempt(self):
        code, sleep = self.install(2)
        self.assertEqual(code, 0)
        self.assertEqual(sleep.call_count, 2)
        self.assertEqual((self.sdk / 'calls').read_text(), '3')
        for attempt in (1, 2):
            report = json.loads((self.output / f'attempt-{attempt}.json').read_text())
            self.assertEqual(report['exit_code'], 7)
            archive = report['archives'][0]
            self.assertEqual(archive['bytes'], 12)
            self.assertFalse(archive['valid_zip'])
            self.assertEqual(len(archive['sha1']), 40)
            self.assertIn('zip_error', archive)
            self.assertEqual(archive['prefix_hex'], b'PK truncated'.hex())
            self.assertIn('Error on ZipFile unknown archive',
                          (self.output / f'attempt-{attempt}.log').read_text())
        self.assertEqual(json.loads((self.output / 'attempt-3.json').read_text())['exit_code'], 0)

    def test_persistent_failure_stops_after_three_attempts_and_stays_failed(self):
        code, sleep = self.install(20)
        self.assertEqual(code, 7)
        self.assertEqual((self.sdk / 'calls').read_text(), '3')
        self.assertEqual(sleep.call_count, 2)
        self.assertTrue((self.output / 'attempt-3.json').exists())

    def test_first_success_does_not_retry(self):
        code, sleep = self.install(0)
        self.assertEqual(code, 0)
        sleep.assert_not_called()
        self.assertEqual((self.sdk / 'calls').read_text(), '1')
        self.assertTrue((self.output / 'context.json').exists())

    def test_cli_keeps_artifacts_in_source_checkout_when_tooling_is_elsewhere(self):
        result = subprocess.run(
            [sys.executable, str(Path(installer.__file__).resolve()),
             'emulator', 'system-images;android-36;google_apis;x86_64'],
            cwd=self.root,
            env={**os.environ, 'ANDROID_HOME': str(self.sdk), 'FAKE_SDK_FAILURES': '0'},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / 'build/sdk-install/attempt-1.log').exists())


if __name__ == '__main__':
    unittest.main()
