#!/usr/bin/env python3
"""Read-only Android resource comparison; never captures chat text or credentials.

Keep the scenario stable while recording (idle chat, typing, streaming, Home).
CPU percentages use one core = 100%; the first top sample is discarded.
No packages are stopped, data cleared, or battery statistics reset.
"""
import argparse
import collections
import datetime
import json
import re
import subprocess
import time
from pathlib import Path


def parse_top(output):
    samples = []
    sample = None
    for line in output.splitlines():
        if line.startswith("Tasks:"):
            sample = {"processes": []}
            samples.append(sample)
        elif sample is not None:
            cpu = re.search(r"(\d+)%cpu.*?([\d.]+)%idle", line)
            row = re.fullmatch(r"\s*(\d+)\s+([\d.]+)\s+(\S+)\s+(.+?)\s*", line)
            if cpu:
                sample["capacity_percent"] = int(cpu[1])
                sample["busy_percent"] = int(cpu[1]) - float(cpu[2])
            elif row:
                sample["processes"].append({
                    "pid": int(row[1]), "cpu_percent": float(row[2]),
                    "rss": row[3], "process": row[4],
                })
    return samples[1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--package", default="com.tarkilhk.wing")
    parser.add_argument("--label", required=True)
    parser.add_argument("--samples", type=int, default=12)
    parser.add_argument("--interval", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-app-cpu", type=float,
                        help="Optional scenario-specific mean CPU budget (one core = 100).")
    args = parser.parse_args()
    if args.samples < 1 or args.interval < 1:
        parser.error("samples and interval must be positive")
    if not re.fullmatch(r"[a-zA-Z0-9_.]+", args.package):
        parser.error("invalid package")
    adb = ["adb", "-s", args.serial]

    def shell(*words, timeout=20):
        return subprocess.check_output(adb + ["shell", *words], text=True, timeout=timeout)

    def snapshot():
        battery = shell("dumpsys", "battery")
        thermal = shell("dumpsys", "thermalservice")
        memory = shell("cat", "/proc/meminfo")
        activity = shell("dumpsys", "activity", "activities")
        package = shell("dumpsys", "package", args.package)
        app_memory = shell("dumpsys", "meminfo", args.package)
        processes = subprocess.run(adb + ["shell", "pidof", args.package],
                                   capture_output=True, text=True, timeout=20)
        fields = {}
        for key in ("level", "temperature", "voltage", "Charge counter", "AC powered", "USB powered", "Wireless powered"):
            match = re.search(r"^\s*" + re.escape(key) + r":\s*(.+)$", battery, re.M)
            if match:
                fields[key] = match[1]
        return {
            "time_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "battery": fields,
            "thermal_status": next(iter(re.findall(r"^Thermal Status: (\d+)$", thermal, re.M)), None),
            "memory_kb": {k: int(v) for k, v in re.findall(
                r"^(MemAvailable|SwapTotal|SwapFree):\s+(\d+)", memory, re.M)},
            "foreground_packages": sorted(set(re.findall(
                r"(?:topResumedActivity|ResumedActivity):?=.*?\s([\w.]+)/", activity))),
            "app_version": re.findall(r"\bversion(?:Code|Name)=\S+", package)[:2],
            "app_memory_kb": {k: int(v) for k, v in re.findall(
                r"(TOTAL PSS|TOTAL RSS|TOTAL SWAP PSS):\s+(\d+)", app_memory)},
            "app_pids": processes.stdout.strip().split() if processes.returncode == 0 else [],
        }

    start = snapshot()
    # All processes are needed: a quiet target must not disappear below a top-N cutoff.
    began = time.monotonic()
    raw = shell("top", "-b", "-n", str(args.samples + 1), "-d", str(args.interval),
                "-m", "10000", "-o", "PID,%CPU,RES,NAME", "-s", "2",
                timeout=(args.samples + 1) * args.interval + 30)
    elapsed = time.monotonic() - began
    end = snapshot()
    samples = parse_top(raw)
    if len(samples) != args.samples or any(not s["processes"] for s in samples):
        raise SystemExit("Incomplete top samples; no performance verdict produced.")
    totals = collections.defaultdict(float)
    for sample in samples:
        for process in sample["processes"]:
            totals[process["process"]] += process["cpu_percent"]
    means = sorted(({"process": p, "mean_cpu_percent": round(c / len(samples), 2)}
                    for p, c in totals.items()), key=lambda p: p["mean_cpu_percent"], reverse=True)
    app_mean = sum(p["mean_cpu_percent"] for p in means
                   if p["process"] == args.package or p["process"].startswith(args.package + ":"))
    present = all(any(p["process"] == args.package for p in s["processes"]) for s in samples)
    report = {"label": args.label, "package": args.package,
              "device_model": shell("getprop", "ro.product.model").strip(),
              "android_version": shell("getprop", "ro.build.version.release").strip(),
              "interval_seconds": args.interval,
              "elapsed_seconds": round(elapsed, 2), "start": start, "end": end,
              "app_present_every_sample": present, "app_mean_cpu_percent": app_mean,
              "top_processes": means[:15], "samples": samples}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "samples"}, indent=2))
    if args.max_app_cpu is not None:
        if not present or start["app_pids"] != end["app_pids"] or start["app_version"] != end["app_version"]:
            raise SystemExit("INCONCLUSIVE: target absent or restarted/updated during capture.")
        if app_mean > args.max_app_cpu:
            raise SystemExit(f"FAIL: mean app CPU {app_mean:.2f}% exceeds {args.max_app_cpu:.2f}% budget.")
        print("PASS: mean app CPU is within the scenario budget.")


if __name__ == "__main__":
    main()
