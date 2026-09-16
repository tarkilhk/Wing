#!/usr/bin/env python3
"""Check Android's installed Quick Chat shortcut, including its resolved target."""

import argparse
import re
import subprocess


def check_shortcut(adb, serial, package):
    def shell(*args):
        return subprocess.check_output(
            [adb, "-s", serial, "shell", *args], text=True
        )

    dump = shell("dumpsys", "shortcut")
    shortcuts = re.findall(r"ShortcutInfo \{id=new_quick_chat,.*?iconRes=.*?\}", dump, re.S)
    matches = [
        shortcut for shortcut in shortcuts
        if re.search(r"packageName=" + re.escape(package) + r"\s", shortcut)
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected one Quick Chat shortcut for {package}, found {len(matches)}")
    shortcut = matches[0]
    component = re.search(r"\bcmp=([^\s}]+)", shortcut)
    actual = component.group(1) if component else None
    expected = f"{package}/com.tarkilhk.wing.MainActivity"
    if actual != expected:
        raise ValueError(f"Quick Chat targets {actual!r}; expected {expected!r}")
    if "act=com.tarkilhk.wing.action.QUICK_CHAT " not in shortcut:
        raise ValueError("Quick Chat action is missing")
    resolved = shell("cmd", "package", "resolve-activity", "--brief", "-n", actual)
    if "com.tarkilhk.wing.MainActivity" not in resolved and f"{package}/.MainActivity" not in resolved:
        raise ValueError(f"Quick Chat target does not resolve: {resolved.strip()}")
    print(f"PASS: New Quick Chat resolves to {expected}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--package", default="com.tarkilhk.wing")
    args = parser.parse_args()
    check_shortcut(args.adb, args.serial, args.package)
