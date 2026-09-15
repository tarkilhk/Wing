#!/usr/bin/env python3
"""Verify every distributable APK before allowing release publication."""

import os
from pathlib import Path
import re
import subprocess

from release import ROOT, current_version


def verify():
    version, build = current_version()
    version_name = ".".join(map(str, version))
    apk_dir = ROOT / "build/app/outputs/flutter-apk"
    abi_codes = {"armeabi-v7a": 1, "arm64-v8a": 2, "x86_64": 3}
    expected = {f"app-{abi}-release.apk" for abi in abi_codes}
    actual = {path.name for path in apk_dir.glob("*.apk")}
    if actual != expected:
        raise ValueError(f"Expected exactly {sorted(expected)}, found {sorted(actual)}")
    sdk = Path(os.environ["ANDROID_HOME"])
    versions = [path for path in (sdk / "build-tools").iterdir()
                if re.fullmatch(r"\d+\.\d+\.\d+", path.name)]
    build_tools = max(versions, key=lambda path: tuple(map(int, path.name.split("."))))
    certificate = (ROOT / "android/wing-release-certificate.sha256").read_text().strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", certificate):
        raise ValueError("Invalid pinned signing certificate")
    for abi, code in abi_codes.items():
        apk = apk_dir / f"app-{abi}-release.apk"
        badging = subprocess.check_output([str(build_tools / "aapt"), "dump", "badging", str(apk)], text=True)
        package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
        expected_package = ("com.tarkilhk.wing", str(build * 10 + code), version_name)
        if not package or package.groups() != expected_package:
            raise ValueError(f"{apk.name}: incorrect package or version")
        if "application-debuggable" in badging:
            raise ValueError(f"{apk.name}: release must not be debuggable")
        native = re.search(r"^native-code: (.+)$", badging, re.M)
        if not native or native.group(1).strip() != f"'{abi}'":
            raise ValueError(f"{apk.name}: incorrect native architecture")
        signed = subprocess.check_output(
            [str(build_tools / "apksigner"), "verify", "--print-certs", str(apk)],
            text=True, stderr=subprocess.STDOUT,
        )
        fingerprints = re.findall(r"^Signer #\d+ certificate SHA-256 digest: (\w+)$", signed, re.M)
        if [value.lower() for value in fingerprints] != [certificate]:
            raise ValueError(f"{apk.name}: incorrect signing certificate")
        print(f"Verified {apk.name}: {version_name}, versionCode {build * 10 + code}, expected release certificate")


if __name__ == "__main__":
    verify()
