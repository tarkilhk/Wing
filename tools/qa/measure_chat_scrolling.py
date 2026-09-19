#!/usr/bin/env python3
"""Measure an already-open Chats screen in a profile build; no server mutations.

Build with -t tools/performance/chat_frames.dart. Configure the real connection
on the device first. This script only scrolls and pulls to refresh. Keep builds
and tests stopped while it runs. Output includes timing metadata, never chat text.
"""
import argparse
import json
import math
import re
import subprocess
import time
from pathlib import Path
from wing_perf_client import WingPerfClient

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--serial", required=True)
parser.add_argument("--package", default="com.tarkilhk.wing.dev")
parser.add_argument("--label", required=True)
parser.add_argument("--runs", type=int, default=3)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be positive")
adb = ["adb", "-s", args.serial]

def call(*words):
    return subprocess.check_output(adb + list(words), text=True, timeout=20)

foreground = call("shell", "dumpsys", "activity", "activities")
if not any(args.package + "/" in line and "ResumedActivity" in line
           for line in foreground.splitlines()):
    raise SystemExit("Open Chats and dismiss permission dialogs before measuring.")
pid = call("shell", "pidof", args.package).strip().split()[0]
size = re.findall(r"(\d+)x(\d+)", call("shell", "wm", "size"))[-1]
width, height = map(int, size)
metadata = {
    "label": args.label, "serial": args.serial, "package": args.package,
    "size": [width, height], "density": call("shell", "wm", "density").strip(),
    "version": [line.strip() for line in call("shell", "dumpsys", "package", args.package).splitlines()
                if "versionName=" in line or "versionCode=" in line][:2],
    "android": call("shell", "getprop", "ro.build.version.release").strip(),
    "renderer_note": "Record device GPU, actual refresh rate and build revision alongside this file.",
}
marker = "WingScroll" + str(time.time_ns())

def swipe(up):
    x, high, low = round(width * .46), round(height * .42), round(height * .73)
    call("shell", "input", "swipe", str(x), str(low if up else high),
         str(x), str(high if up else low), "350")

def metric(samples):
    if not samples:
        raise RuntimeError("No frame samples: use the benchmark profile entry point.")
    values = sorted(samples)
    def percentile(p):
        return values[max(0, math.ceil(len(values) * p) - 1)] / 1000
    return {"frames": len(values), "p50_ms": percentile(.5),
            "p95_ms": percentile(.95), "p99_ms": percentile(.99),
            "max_ms": max(values) / 1000,
            "over_16_ms": sum(value > 16000 for value in values)}

client = WingPerfClient(args.serial, args.package)
try:
    ready = client.action("snapshot")
    if ready["loading"] or not ready["initialized"]:
        raise SystemExit("Wait for the initial Chats load to finish before measuring.")
finally:
    client.close()

for run in range(1, args.runs + 1):
    # Return to the start without causing extra pull-to-refresh requests.
    with WingPerfClient(args.serial, args.package) as client:
        client.action("top")
    time.sleep(2)
    call("shell", "log", "-t", "WingPerf", f"{marker} {run} START")
    started = time.monotonic()
    swipe(False)
    for _ in range(4):
        swipe(True)
    count = 0
    while time.monotonic() - started < 30:
        swipe(count % 2 == 0)
        count += 1
        time.sleep(.1)
    call("shell", "log", "-t", "WingPerf", f"{marker} {run} END")
    print(f"Run {run}: {time.monotonic() - started:.1f}s, {count + 5} gestures", flush=True)

log = call("logcat", "-d", "-s", "flutter:I", "WingPerf:I")
results = []
for run in range(1, args.runs + 1):
    active, build, raster = False, [], []
    for line in log.splitlines():
        if f"{marker} {run} START" in line:
            active = True
        elif f"{marker} {run} END" in line:
            active = False
        elif active and re.search(r"\s" + pid + r"\s", line):
            match = re.search(r"\[WingPerf\] frames buildUs=([\d,]+) rasterUs=([\d,]+)", line)
            if match:
                build.extend(map(int, match[1].split(",")))
                raster.extend(map(int, match[2].split(",")))
    results.append({"run": run, "build": metric(build), "raster": metric(raster)})
report = {"environment": metadata, "runs": results}
args.output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
