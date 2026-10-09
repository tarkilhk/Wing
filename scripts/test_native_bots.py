#!/usr/bin/env python3
"""Focused Android Bots acceptance. Obtain an emulator/build turn first."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.tarkilhk.wing.dev"
STAGE = "code_cache/wing-bots-stage.json"
ACK = "code_cache/wing-bots-ack"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--source-directory", type=Path, default=ROOT)
    parser.add_argument("--name", help="Recover only the named native case")
    args = parser.parse_args()
    source = args.source_directory.resolve()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)

    def adb(*command, required=True, data=None):
        result = subprocess.run(["adb", "-s", args.device, *command], input=data,
                                capture_output=True, timeout=20)
        if required and result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace"))
        return result

    def shell(*command):
        return adb("shell", *command).stdout.decode().strip()

    if not args.device.startswith("emulator-") or shell("getprop", "ro.kernel.qemu") != "1":
        raise ValueError("Use an exclusively allocated disposable emulator")

    def keyboard_visible():
        return bool(re.search(r"mInputShown=true|mIsInputViewShown=true",
                              shell("dumpsys", "input_method")))

    original = {"size": shell("wm", "size"), "density": shell("wm", "density"),
                "font": shell("settings", "get", "system", "font_scale"),
                "night": shell("cmd", "uimode", "night").split(": ")[-1]}
    records, seen = [], set()
    process = None
    receipt = {"device": args.device, "result": "incomplete",
               "source": str(source), "scope": args.name or "four theme/text cases",
               "original_settings": original, "no_live_server": True,
               "target_sha256": hashlib.sha256(
                   (source / "integration_test/bots_native_test.dart").read_bytes()).hexdigest()}
    try:
        # A terminated Flutter host can leave its previous test running in the
        # Android process. Stop this owned QA package before polling its bridge.
        shell("am", "force-stop", PACKAGE)
        adb("shell", "run-as", PACKAGE, "rm", "-f", STAGE, ACK, required=False)
        shell("wm", "size", "840x2215" if args.name and "large" in args.name else "1024x2215")
        shell("wm", "density", "420")
        shell("settings", "put", "system", "font_scale", "2.0" if args.name and "large" in args.name else "1.0")
        command = ["flutter", "test", "--no-pub", "--no-uninstall", "-d", args.device,
                   "--reporter", "expanded", "--dart-define=BOTS_NATIVE_INPUT=true",
                   "integration_test/bots_native_test.dart"]
        if args.name:
            command.extend(["--name", args.name])
        log = output / "native-test.log"
        with log.open("w") as stream:
            process = subprocess.Popen(command, cwd=source, stdout=stream, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 1200
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise TimeoutError("Native Bots scope exceeded twenty minutes")
                raw = adb("shell", "run-as", PACKAGE, "cat", STAGE, required=False)
                try:
                    stage = json.loads(raw.stdout)
                except (ValueError, UnicodeDecodeError):
                    time.sleep(.2)
                    continue
                if stage["token"] in seen:
                    time.sleep(.1)
                    continue
                name, action = stage["name"], stage["action"]
                if action == "configure":
                    large = "-large-" in name
                    shell("wm", "size", "840x2215" if large else "1024x2215")
                    shell("wm", "density", "420")
                    shell("settings", "put", "system", "font_scale", "2.0" if large else "1.0")
                    shell("cmd", "uimode", "night", "yes" if name.startswith("dark") else "no")
                    shell("wm", "dismiss-keyguard")
                    time.sleep(.8)
                elif action in ("type", "append"):
                    end = time.monotonic() + 5
                    while not keyboard_visible() and time.monotonic() < end:
                        time.sleep(.1)
                    if not keyboard_visible():
                        raise RuntimeError("Android keyboard did not open at " + name)
                    if action == "append":
                        shell("input", "keyevent", "KEYCODE_MOVE_END")
                    shell("input", "text", stage["text"].replace(" ", "%s"))
                    time.sleep(.5)
                elif action == "hide-keyboard":
                    # The read-only retry state can already dismiss the IME.
                    # A stale Android show-request flag must not pop its route.
                    if stage["ime_insets_bottom"] > 0:
                        shell("input", "keyevent", "KEYCODE_BACK")
                    # Flutter completes the platform transition after the stage
                    # acknowledgement; the native test asserts zero IME insets.
                    time.sleep(.5)
                elif action == "back":
                    shell("input", "keyevent", "KEYCODE_BACK")
                    time.sleep(.5)
                elif action == "picker-cancel":
                    activity = shell("dumpsys", "activity", "activities")
                    resumed = "\n".join(line for line in activity.splitlines()
                                        if "ResumedActivity" in line)
                    if not re.search(r"documentsui|DocumentsActivity|PickActivity", resumed):
                        (output / (name + "-activity.txt")).write_text(activity)
                        raise RuntimeError("Android document picker did not open")
                    shell("input", "keyevent", "KEYCODE_BACK")
                    time.sleep(.5)
                elif action != "capture":
                    raise ValueError("Unknown native action " + action)
                stage["keyboard_visible"] = keyboard_visible()
                if "keyboard" in stage and stage["keyboard"] != stage["keyboard_visible"]:
                    raise RuntimeError("Unexpected native keyboard state at " + name)
                window = shell("dumpsys", "window")
                focus = "\n".join(line for line in window.splitlines()
                                  if "mCurrentFocus=" in line)
                stage["window_focus"] = focus.strip()
                png = adb("exec-out", "screencap", "-p").stdout
                if not png.startswith(b"\x89PNG"):
                    raise RuntimeError("Android screenshot was not PNG")
                (output / (name + ".png")).write_bytes(png)
                if re.search(r"Application Error|Application Not Responding|ANR", focus,
                             flags=re.IGNORECASE):
                    (output / (name + "-window.txt")).write_text(window)
                    raise RuntimeError("Android error overlay at " + name)
                records.append(stage)
                (output / "checkpoints.json").write_text(json.dumps(records, indent=2) + "\n")
                adb("shell", "run-as", PACKAGE, "tee", ACK, data=stage["token"].encode())
                seen.add(stage["token"])
                print("Native Bots checkpoint:", name, flush=True)
            if process.returncode:
                print(log.read_text()[-10000:], flush=True)
                raise RuntimeError("Native Bots test failed: " + str(log))
        process = None
        receipt["result"] = "passed"
        receipt["completed_cases"] = [r["name"] for r in records if r["name"].endswith("complete")]
        print(log.read_text()[-1800:], flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=20)
        for key in ("size", "density"):
            value = original[key].split("Override " + key + ": ")[-1].strip()
            shell("wm", key, value if "Override " in original[key] else "reset")
        if original["font"] == "null":
            shell("settings", "delete", "system", "font_scale")
        else:
            shell("settings", "put", "system", "font_scale", original["font"])
        if original["night"] in ("yes", "no", "auto", "custom"):
            shell("cmd", "uimode", "night", original["night"])
        receipt["checkpoint_count"] = len(records)
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
