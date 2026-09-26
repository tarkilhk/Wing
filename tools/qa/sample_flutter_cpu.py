#!/usr/bin/env python3
"""Sample an AOT profile build through a private ADB tunnel.

Build tools/performance/chat_frames.dart in profile mode first. Keep the device
on the scenario being measured. Exports function names and aggregate ticks,
never VM-service tokens, object contents, connection details or message text.
"""
import argparse
import json
import time
from pathlib import Path

from wing_perf_client import WingPerfClient


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--package", default="com.tarkilhk.wing.dev")
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--label", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 60:
        parser.error("seconds must be between 1 and 60")
    with WingPerfClient(args.serial, args.package) as client:
        flags = client.rpc("getFlagList")["flags"]
        original = next(flag["valueAsString"] for flag in flags if flag["name"] == "profiler")
        client.rpc("setFlag", name="profiler", value="true")
        try:
            client.rpc("clearCpuSamples", isolateId=client.isolate)
            memory_before = client.rpc("getMemoryUsage", isolateId=client.isolate)
            start = client.rpc("getVMTimelineMicros")["timestamp"]
            print(f"Sampling {args.label} for {args.seconds}s", flush=True)
            time.sleep(args.seconds)
            end = client.rpc("getVMTimelineMicros")["timestamp"]
            samples = client.rpc("getCpuSamples", isolateId=client.isolate,
                                 timeOriginMicros=start, timeExtentMicros=end - start)
            memory_after = client.rpc("getMemoryUsage", isolateId=client.isolate)
        finally:
            client.rpc("setFlag", name="profiler", value=original)
    functions = [{"name": row["function"].get("name", "<unnamed>"),
                  "source": row.get("resolvedUrl", ""),
                  "inclusive_ticks": row.get("inclusiveTicks", 0),
                  "exclusive_ticks": row.get("exclusiveTicks", 0)}
                 for row in samples.get("functions", [])]
    report = {"label": args.label, "package": args.package,
              "duration_us": end - start, "sample_count": samples["sampleCount"],
              "sample_period_us": samples["samplePeriod"],
              "heap_before": memory_before, "heap_after": memory_after,
              "functions": functions}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({**{k: v for k, v in report.items() if k != "functions"},
                      "top_exclusive": sorted(functions, key=lambda f: f["exclusive_ticks"], reverse=True)[:20],
                      "top_wing_inclusive": sorted(
                          [f for f in functions if f["source"].startswith("package:wing/")],
                          key=lambda f: f["inclusive_ticks"], reverse=True)[:20]}, indent=2))


if __name__ == "__main__":
    main()
