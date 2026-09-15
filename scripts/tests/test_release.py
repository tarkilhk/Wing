import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "checkout"
        self.root.mkdir()
        self.root_patch = patch.object(release, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)
        release.git("init", "-b", "main")
        release.git("config", "user.name", "Release Test")
        release.git("config", "user.email", "release@example.invalid")
        (self.root / "android/app").mkdir(parents=True)
        (self.root / "android/app/build.gradle.kts").write_text("val minimumInstalledVersionCode = 2127\n")
        self.write_version("2.36.15+2232")
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n\n## Unreleased\n\n### Fixed\n\n- Fix a bug.\n\n"
            "## [2.36.15+2232] - 2026-09-15\n\n- Previous release.\n"
        )
        release.git("add", ".")
        release.git("commit", "-m", "Initial source")
        (self.root / "scripts").mkdir()
        (self.root / "scripts/release-history-start").write_text(release.git("rev-parse", "HEAD") + "\n")
        release.git("add", ".")
        release.git("commit", "-m", "Set release history boundary")
        self.remote = Path(self.temp.name) / "origin.git"
        release.git("init", "--bare", str(self.remote))
        release.git("remote", "add", "origin", str(self.remote))
        release.git("push", "origin", "main")

    def write_version(self, value):
        (self.root / "pubspec.yaml").write_text(f"name: wing\nversion: {value}\n")

    def commit_and_push(self):
        release.git("add", ".")
        release.git("commit", "-m", "Prepare release")
        release.git("push", "origin", "main")

    def test_bumps_and_build_number(self):
        for bump, expected in [("patch", "2.36.16+2233"), ("minor", "2.37.0+2233"), ("major", "3.0.0+2233")]:
            with self.subTest(bump=bump):
                release.git("restore", "pubspec.yaml", "CHANGELOG.md")
                release.prepare(bump, False)
                self.assertIn(f"version: {expected}", (self.root / "pubspec.yaml").read_text())
                changelog = (self.root / "CHANGELOG.md").read_text()
                self.assertIn(f"## Unreleased\n\n## [{expected.split('+')[0]}] - ", changelog)
                self.assertEqual(release.release_notes(release.current_version()[0]), "### Fixed\n\n- Fix a bug.\n")
                self.assertIn("- Previous release.", changelog)

    def test_prepare_dry_run_is_read_only(self):
        release.prepare("minor", True)
        self.assertEqual(release.git("status", "--porcelain"), "")

    def test_empty_notes_do_not_modify_version(self):
        (self.root / "CHANGELOG.md").write_text("# Changelog\n\n## Unreleased\n\n### Fixed\n")
        with self.assertRaisesRegex(ValueError, "Add release notes"):
            release.prepare("patch", False)
        self.assertEqual(release.current_version(), ((2, 36, 15), 2232))

    def test_cannot_prepare_twice_without_new_notes(self):
        release.prepare("patch", False)
        with self.assertRaisesRegex(ValueError, "Add release notes"):
            release.prepare("patch", False)
        self.assertEqual(release.current_version(), ((2, 36, 16), 2233))

    def test_tag_must_match_version(self):
        with self.assertRaisesRegex(ValueError, "must match"):
            release.check_version("v2.36.16")

    def test_floor_and_android_limit(self):
        for value in ["2.36.15+2127", "2.36.15+210000000"]:
            self.write_version(value)
            with self.assertRaises(ValueError):
                release.check_version()

    def test_new_release_must_increase_version_and_build(self):
        release.git("tag", "v2.36.15")
        for value in ["2.36.16+2232", "2.36.14+2233"]:
            self.write_version(value)
            with self.assertRaisesRegex(ValueError, "advance together"):
                release.check_version(release.release_tag(release.current_version()[0]))
        self.write_version("2.36.16+2233")
        release.check_version("v2.36.16")

    def test_check_allows_unchanged_released_version_for_normal_ci(self):
        release.git("tag", "v2.36.15")
        release.check_version()

    def test_first_wing_release_ignores_inherited_application_tags(self):
        release.git("tag", "v2.36.15", "HEAD~1")
        boundary = release.git("rev-parse", "HEAD")
        (self.root / "scripts/release-history-start").write_text(boundary + "\n")
        self.write_version("1.0.0+2233")
        release.check_version("v1.0.0")

    def test_wing_versions_still_cannot_move_backwards(self):
        self.write_version("1.1.0+2234")
        self.commit_and_push()
        release.git("tag", "v1.1.0")
        self.write_version("1.0.0+2235")
        with self.assertRaisesRegex(ValueError, "advance together"):
            release.check_version("v1.0.0")

    def test_invalid_history_boundary_fails_closed(self):
        (self.root / "scripts/release-history-start").write_text("main\n")
        with self.assertRaisesRegex(ValueError, "full commit SHA"):
            release.check_version()

    def test_publishing_pushes_only_annotated_version_tag(self):
        release.prepare("patch", False)
        self.commit_and_push()
        release.publish(False)
        self.assertEqual(release.git("cat-file", "-t", "refs/tags/v2.36.16"), "tag")
        remote_commit = release.git("ls-remote", "origin", "refs/tags/v2.36.16^{}").split()[0]
        self.assertEqual(remote_commit, release.git("rev-parse", "HEAD"))
        with self.assertRaisesRegex(ValueError, "already exists"):
            release.publish(False)

    def test_publish_dry_run_creates_no_tag(self):
        release.prepare("patch", False)
        self.commit_and_push()
        release.publish(True)
        self.assertEqual(release.git("tag", "--list"), "")
        self.assertEqual(release.git("ls-remote", "--tags", "origin"), "")

    def test_publish_refuses_dirty_tree(self):
        release.prepare("patch", False)
        with self.assertRaisesRegex(ValueError, "Commit or stash"):
            release.publish(False)

    def test_publish_refuses_unmerged_branch(self):
        release.git("switch", "-c", "release-prep")
        with self.assertRaisesRegex(ValueError, "Publish from main"):
            release.publish(False)

    def test_publish_refuses_unpushed_commit(self):
        release.prepare("patch", False)
        release.git("add", ".")
        release.git("commit", "-m", "Not on remote")
        with self.assertRaisesRegex(ValueError, "must match origin/main"):
            release.publish(False)
        self.assertEqual(release.git("tag", "--list"), "")

    def test_publish_requires_dated_release_notes(self):
        self.write_version("2.36.16+2233")
        self.commit_and_push()
        with self.assertRaisesRegex(ValueError, "no dated entry"):
            release.publish(False)
        self.assertEqual(release.git("tag", "--list"), "")

    def test_rejects_malformed_versions(self):
        for value in ["2.1+2233", "02.1.1+2233", "2.1.1+0", "2.1.1-beta+2233"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.parse_version(f"version: {value}\n")


if __name__ == "__main__":
    unittest.main()
