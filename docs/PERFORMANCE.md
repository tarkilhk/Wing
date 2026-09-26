# Performance investigation

Measure the phone and Wing separately. A hot device can make Wing slow even
when another process supplies most of the sustained load. CPU use identifies
work; it does not measure an app's share of battery discharge.

## Repeatable phone capture

Run from the checkout with an authorized ADB device:

```sh
python3 tools/qa/record_phone_resources.py --serial <device> --label idle-chat --samples 12 --interval 5 --output build/performance/idle-chat.json
```

The recorder reads all processes, discards `top`'s initial sample, and reports
mean CPU with **one core = 100%**. It captures the installed Wing version and
PID, foreground package, app PSS/RSS, system available memory/swap, battery
charge counter/temperature, and thermal status at both ends. It does not stop
apps, reset statistics, capture content, or contact Hermes. Reports include
process names; keep them under ignored `build/` and review before sharing.

An optional `--max-app-cpu <percent>` makes a known scenario fail its selected
budget. Establish that budget from a stable, repeated baseline; it is not a
universal threshold. A missing/restarted/updated target is inconclusive.
Foreground samples at the endpoints do not prove that the whole interval was
idle: record the actions performed during each capture.

Hold brightness, refresh rate, network, charging, keyboard and workload steady.
Let the device cool first. Stop host builds during phone timing runs. Collect
three runs per scenario; compare the same installed build and workload before
and after changing one variable. Do not attribute an uncontrolled temperature
drop or a different typing workload to a code change.

## Investigation matrix

| Scenario | Duration/workload | Signals and acceptance |
| --- | --- | --- |
| Chats and idle conversation | 60 seconds each, keyboard closed/open | CPU and scheduled frames settle; inspect continuous animations, timers and controller updates if they do not. |
| Typing | 200 edits at a fixed cadence, short and long histories | Measure Flutter build/raster p50/p95/p99 plus input-to-present latency. Draft edits must cause zero unchanged transcript builds and zero workspace monitoring notifications. |
| Streaming | Replay the same token/tool-event fixture and Markdown answer | CPU, allocation/GC, frame deadlines, response-to-input latency; compare event frequency with UI update frequency. No missing terminal events or approvals. |
| Navigation soak | Repeat open/close of the same 20 chats for 20 minutes | Compare retained heap, PSS, controllers, sockets and timers after settling/GC. Memory should plateau for a fixed dataset; distinguish caches from retained owners. |
| Background, no work | Home, then screen off, 10 minutes | Check CPU wakeups, polling, sockets and wake locks; distinguish expected retained state from recurring work. |
| Background, active work | Same known work, then completion | Monitoring continues while needed and releases when finished; delivery and recovery still work. |
| Battery | Matched 20–30 minute unplugged runs after cooling | Charge-counter slope, thermal status and available power rails; keep screen/network/other apps constant. Short battery-percent samples cannot establish savings. |

Start with the largest measured cost. If another app dominates, repeat after
the owner closes that app; do not silently disable personal services. If Wing
still dominates, collect a CPU profile before choosing another optimization.

## Flutter and Android traces

Use an AOT **profile** build on a physical phone for Flutter timing, as described
in [Flutter's profiling guide](https://docs.flutter.dev/perf/ui-performance).
Debug widget-test elapsed times are useful diagnostics, not device latency.
The profile variant installs as `com.tarkilhk.wing.dev`, separate from release
connections and drafts. Configure an equivalent test connection/data set there.

```sh
flutter build apk --profile -t tools/performance/chat_frames.dart
```

The existing entry point records Flutter build/raster timings for all screens;
its `snapshot`/`top`/`refresh` service extensions and
`tools/qa/measure_chat_scrolling.py` specifically target the Chats browser.
Use DevTools CPU sampling and the Performance view for conversation typing and
streaming. Retain both timing distributions and the CPU stacks that explain
expensive frames. Use the device's actual refresh deadline (16.7 ms at 60 Hz,
8.3 ms at 120 Hz), rather than treating the scrolling script's fixed 16 ms count
as a universal frame budget.

[Android system traces](https://developer.android.com/topic/performance/tracing/profile-types-overview)
separate time spent executing from time waiting to be scheduled. Capture
scheduler activity, CPU frequencies, frame timelines, thermal changes and wake
locks when heat or system contention appears. Android `gfxinfo` alone does not
establish Flutter build/raster performance.

[Power Profiler](https://developer.android.com/studio/profile/power-profiler)
data depends on hardware support. Do not assume a Galaxy exposes Pixel ODPM
rails or infer per-app energy from whole-device battery counters.

## Typing regression boundary

```sh
flutter test test/conversation_work_budget_test.dart
```

This test drives the real conversation screen through draft and queued-edit
input, counts unchanged message rebuilds and workspace notifications, and
checks persistence and programmatic text updates. Draft-only edits use
`ProfileWorkspaceController.composerChanges`; other state transitions still
refresh the workspace. The composer listens separately so keystrokes do not
trigger transcript rendering, reading-snapshot scans or notification-input
publication. Draft saving remains ordered and immediate.

Run the composer, queue, voice, draft recovery, notification, streaming-scroll
and reading-snapshot suites when changing this boundary. This regression
protects unnecessary work, not end-to-end keyboard latency or battery life.
