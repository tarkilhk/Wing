#!/usr/bin/env python3
"""Check Android's installed launcher shortcuts and their resolved targets."""

import argparse
import re
import subprocess


def check_shortcut(adb, serial, package):
    def shell(*args):
        return subprocess.check_output(
            [adb, "-s", serial, "shell", *args], text=True
        )

    dump = shell("dumpsys", "shortcut")
    expected_actions = {
        "new_quick_chat": "QUICK_CHAT",
        "activity": "ACTIVITY",
        "search_chats": "SEARCH_CHATS",
    }
    expected = f"{package}/com.tarkilhk.wing.MainActivity"
    for shortcut_id, action in expected_actions.items():
        matches = [
            match.group(0)
            for match in re.finditer(r"ShortcutInfo \{id=([^,]+),.*?iconRes=.*?\}", dump, re.S)
            if match.group(1) == shortcut_id
            and re.search(r"packageName=" + re.escape(package) + r"\s", match.group(0))
        ]
        if len(matches) != 1:
            raise ValueError(f"Expected one {shortcut_id} shortcut for {package}, found {len(matches)}")
        shortcut = matches[0]
        component = re.search(r"\bcmp=([^\s}]+)", shortcut)
        actual = component.group(1) if component else None
        if actual != expected:
            raise ValueError(f"{shortcut_id} targets {actual!r}; expected {expected!r}")
        if f"act=com.tarkilhk.wing.action.{action} " not in shortcut:
            raise ValueError(f"{shortcut_id} action is missing")
        resolved = shell("cmd", "package", "resolve-activity", "--brief", "-n", actual)
        if "com.tarkilhk.wing.MainActivity" not in resolved and f"{package}/.MainActivity" not in resolved:
            raise ValueError(f"{shortcut_id} target does not resolve: {resolved.strip()}")
        print(f"PASS: {shortcut_id} resolves to {expected} with action {action}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--package", default="com.tarkilhk.wing")
    args = parser.parse_args()
    check_shortcut(args.adb, args.serial, args.package)
