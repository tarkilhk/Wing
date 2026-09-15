#!/usr/bin/env python3
"""Prepare and trigger Wing releases using Python 3 and Git only."""

import argparse
from datetime import date
from pathlib import Path
import re
import subprocess
import sys


# Run from the source checkout root. CI may load tooling from a newer workflow
# revision while building an existing immutable source tag.
ROOT = Path.cwd()
SEMVER = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
VERSION = re.compile(rf"^version: ({SEMVER})\+([1-9][0-9]*)$", re.M)
TAG = re.compile(rf"v{SEMVER}")


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.strip()


def parse_version(text):
    matches = list(VERSION.finditer(text))
    if len(matches) != 1:
        raise ValueError("pubspec.yaml must declare one version: MAJOR.MINOR.PATCH+BUILD")
    match = matches[0]
    return tuple(map(int, match.group(2, 3, 4))), int(match.group(5))


def version_text(version, build):
    return f"{'.'.join(map(str, version))}+{build}"


def release_tag(version):
    return "v" + ".".join(map(str, version))


def current_version():
    return parse_version((ROOT / "pubspec.yaml").read_text(encoding="utf-8"))


def is_ancestor(ancestor, ref):
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, ref], cwd=ROOT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode not in (0, 1):
        result.check_returncode()
    return result.returncode == 0


def check_version(tag=None):
    version, build = current_version()
    # Wing starts its own release series at the committed package rename.
    # Inherited Hermes tags are a different application's release history.
    history_start = (ROOT / "scripts/release-history-start").read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", history_start) or not is_ancestor(history_start, "HEAD"):
        raise ValueError("Release history start must be a full commit SHA ancestral to HEAD")
    gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    floor = re.search(r"val minimumInstalledVersionCode = (\d+)", gradle)
    if not floor or build <= int(floor.group(1)):
        raise ValueError("Build number must exceed the Gradle installed-version floor")
    if build * 10 + 3 > 2100000000:
        raise ValueError("ABI-split versionCode exceeds Android's maximum")
    if tag is not None and tag != release_tag(version):
        raise ValueError(f"Tag {tag} must match {release_tag(version)}")
    for previous_tag in git("tag", "--list", "v*").splitlines():
        if not TAG.fullmatch(previous_tag) or previous_tag == tag:
            continue
        if not is_ancestor(history_start, f"refs/tags/{previous_tag}"):
            continue
        previous_version, previous_build = parse_version(
            git("show", f"refs/tags/{previous_tag}:pubspec.yaml")
        )
        if tag is not None:
            invalid = version <= previous_version or build <= previous_build
        else:
            invalid = version < previous_version or build < previous_build
            # Normal APK builds can keep the current release version.
            invalid |= version > previous_version and build == previous_build
        if invalid:
            raise ValueError(f"Invalid version/build progression beyond {previous_tag} ({previous_build})")
    print(f"Verified {release_tag(version)}; internal ARM64 versionCode {build * 10 + 2}")
    return version, build


def unreleased_section(text):
    headings = list(re.finditer(r"^## Unreleased\s*$", text, re.M))
    if len(headings) != 1:
        raise ValueError("CHANGELOG.md must have exactly one '## Unreleased' heading")
    heading = headings[0]
    next_heading = re.search(r"^## ", text[heading.end():], re.M)
    end = heading.end() + next_heading.start() if next_heading else len(text)
    notes = text[heading.end():end].strip()
    if not re.search(r"^[-*] \S", notes, re.M):
        raise ValueError("Add release notes under '## Unreleased' first")
    return heading.start(), end, notes


def release_notes(version):
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = re.search(
        rf"^## \[{re.escape(release_tag(version)[1:])}\] - \d{{4}}-\d{{2}}-\d{{2}}\s*$",
        text, re.M,
    )
    if not heading:
        raise ValueError("Changelog has no dated entry for the current version; run prepare first")
    notes = re.split(r"^## ", text[heading.end():], maxsplit=1, flags=re.M)[0].strip()
    if not re.search(r"^[-*] \S", notes, re.M):
        raise ValueError("Release changelog entry must contain notes")
    return notes + "\n"


def prepare(bump, dry_run):
    version, build = check_version()
    parts = list(version)
    index = {"major": 0, "minor": 1, "patch": 2}[bump]
    parts[index] += 1
    parts[index + 1:] = [0] * (2 - index)
    new_version, new_build = tuple(parts), build + 1
    if new_build * 10 + 3 > 2100000000:
        raise ValueError("Next ABI-split versionCode exceeds Android's maximum")
    changelog_path = ROOT / "CHANGELOG.md"
    changelog = changelog_path.read_text(encoding="utf-8")
    start, end, notes = unreleased_section(changelog)
    label = release_tag(new_version)[1:]
    if f"## [{label}]" in changelog:
        raise ValueError(f"Changelog already contains {label}")
    new_changelog = (
        changelog[:start] + f"## Unreleased\n\n## [{label}] - {date.today().isoformat()}\n\n"
        + notes + "\n\n" + changelog[end:]
    )
    print(f"{'Would prepare' if dry_run else 'Preparing'} {release_tag(version)[1:]} -> {label}")
    print(f"Files: pubspec.yaml, CHANGELOG.md; release tag: {release_tag(new_version)}")
    if dry_run:
        return
    pubspec_path = ROOT / "pubspec.yaml"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    pubspec_path.write_text(VERSION.sub(f"version: {version_text(new_version, new_build)}", pubspec), encoding="utf-8")
    changelog_path.write_text(new_changelog, encoding="utf-8")
    print("Review and commit these changes, merge to main, then run: python3 scripts/release.py publish")


def publish(dry_run):
    if git("status", "--porcelain"):
        raise ValueError("Commit or stash all changes before publishing")
    if git("branch", "--show-current") != "main":
        raise ValueError("Publish from main after merging the release preparation")
    # No force: conflicting tags must fail, never silently move.
    git("fetch", "origin", "--tags", "+refs/heads/main:refs/remotes/origin/main")
    head = git("rev-parse", "HEAD")
    if head != git("rev-parse", "refs/remotes/origin/main"):
        raise ValueError("Local main must match origin/main; pull or merge your changes first")
    version, build = current_version()
    tag = release_tag(version)
    if git("tag", "--list", tag):
        raise ValueError(f"Tag {tag} already exists; rerun its workflow or prepare a new version")
    check_version(tag)
    release_notes(version)
    print(f"{'Would tag and push' if dry_run else 'Tagging and pushing'} {tag} at {head} to origin")
    if dry_run:
        return
    git("tag", "-a", tag, "-m", f"Wing {tag}", head)
    try:
        git("push", "origin", f"refs/tags/{tag}:refs/tags/{tag}")
    except subprocess.CalledProcessError:
        print(f"Push failed. Local {tag} remains; inspect the remote, then retry git push origin refs/tags/{tag}.", file=sys.stderr)
        raise
    print("GitHub Actions will test, sign, verify and publish the release. Follow the Release workflow in GitHub.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare", help="Bump source version and date the Unreleased notes")
    prep.add_argument("bump", choices=["major", "minor", "patch"])
    prep.add_argument("--dry-run", action="store_true")
    pub = commands.add_parser("publish", help="Tag clean, merged main and push the tag to origin (starts CI)")
    pub.add_argument("--dry-run", action="store_true", help="Validate without creating/pushing a tag; fetches origin")
    check = commands.add_parser("check", help="Validate source version against fetched stable tags")
    check.add_argument("--tag", help="Require this exact new release tag")
    notes = commands.add_parser("notes", help="Write the current release's changelog notes")
    notes.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(args.bump, args.dry_run)
        elif args.command == "publish":
            publish(args.dry_run)
        elif args.command == "check":
            check_version(args.tag)
        else:
            args.output.write_text(release_notes(current_version()[0]), encoding="utf-8")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
