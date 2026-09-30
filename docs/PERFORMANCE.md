# Performance investigation

Measure the phone and Wing separately. A hot device can make Wing slow even
when another process supplies most of the sustained load. CPU use identifies
work; it does not measure an app's share of battery discharge.

## Emulator-first monitoring check

Use a disposable API 36 phone AVD before the physical-phone phase. Build and
install the isolated diagnostic fixture, then run its native checker:

```sh
flutter build apk --debug --no-pub --target-platform android-x64 -t integration_test/background_monitoring_device.dart
adb -s <emulator-id> install -r build/app/outputs/flutter-apk/app-debug.apk
python3 tools/qa/check_background_monitoring.py --serial <emulator-id> --resource-dir build/emulator-acceptance/performance
```

The checker rejects physical devices. It tests idle startup, one shared active
30-second polling timer, timer cancellation after settling, native monitoring
notification and wake-lock release, engine retention/release, notification
privacy/preferences, and forced Doze delivery **with battery exemption**. It
restores its power settings. Stop other QA fixtures and host builds during the
two 35-second resource windows; retain the exact fixture/build and emulator
configuration with the output.

In the 30 September 2026 Android 16 x86_64 debug AVD run, active work produced
one timer and one tick; settled work had zero timers and zero new ticks. Mean
app CPU was 0.6% active and 0.9% settled (one core = 100%); end PSS was 357,079
and 350,874 KiB respectively. These single short debug measurements verify
instrumentation and resource attribution. They are not comparative savings,
release budgets or physical-device battery measurements. The lower settled PSS
does not establish a leak-free navigation soak, and the CPU difference does not
show that idle work uses more energy.

Use the phone matrix below for matched energy, thermal, frame/input latency and
long-duration retention measurements. Repeat background delivery with the
phone's normal and restricted battery/network policy; exempt-emulator Doze
success does not cover OEM restrictions.

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
| Navigation soak | Repeat open/close of the same 20 chats, then an increasing set, for 20 minutes each | Compare retained heap, PSS, controllers, sockets and timers after settling/GC. Settled transcript counts should plateau; distinguish configured owners and active leases from caches. |
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

With that build running, capture a bounded CPU sample without changing the
screen or sending a message:

```sh
python3 tools/qa/sample_flutter_cpu.py --serial <device> --seconds 30 --label idle-chat --output build/performance/idle-chat-cpu.json
```

The sampler uses a private ADB tunnel, records Dart function tick counts and
isolate heap usage, and restores the prior profiler flag afterward. It omits
VM-service credentials and object contents. These are main-isolate CPU samples;
use the resource recorder and Android tracing for raster/native work and other
processes. Sampling overhead means these captures are diagnostic, not battery
benchmarks.

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

## Streaming regression boundary

```sh
flutter test test/streaming_work_budget_test.dart test/markdown_render_reuse_test.dart
```

The streaming workload sends real controller events through an injected gateway
and requires zero saved-Markdown rebuilds while answer chunks arrive. Each
mounted `MarkdownMessageContent` retains its rendered subtree until its content,
streaming mode, deliverable mode, action availability or inherited environment
changes. This also avoids regenerating a stylesheet that would cause
`flutter_markdown` to parse unchanged text again. The retained tree lives only
with its message widget; there is no application-wide message cache.

Reused link and file actions dispatch through the current widget callbacks.
Tests cover changing those callbacks, removing actions, changing content and
switching the theme/viewport. Run the Markdown, deliverable and streaming-scroll
suites too. Workspace status, approvals and live answer text still update through
their existing paths; this optimization changes only unchanged message rendering.

## Reading snapshot regression boundary

```sh
flutter test test/workspace_snapshot_work_budget_test.dart test/workspace_reading_snapshot_test.dart
```

Large reading snapshots are encoded and pruned in a worker isolate. A bounded
size walk keeps small snapshots local to avoid isolate startup overhead. Writes
remain ordered, including a small save following a large background save.
Pruning measures candidate lists once and updates only the shortened list;
sorting no longer serializes each candidate for every comparison. The two MiB
UTF-8 bound and newest-message retention are covered by tests. Draft persistence
does not use this store.

The work-budget test uses 2,400 synthetic messages and checks that an event-loop
turn runs before the large save completes. The original implementation failed
that assertion. On the development host its synchronous call took about
2.8–3.0 seconds; the revised call took about 5–12 ms with a total background save
of 154–206 ms. These debug measurements diagnose the algorithm; they do not
establish phone latency or battery improvement. Snapshot collection in the
controller still runs on the UI isolate and should be included in future CPU
profiles.

During a phone slowdown investigation, a release system trace caught two main
thread CPU slices of 184–189 ms immediately preceding preference writes. That
correlation motivates this fix but does not identify the Dart call stacks.
A separate eight-gesture scroll capture submitted 778 frames without any
32–200 ms inter-submission gaps, and the owner subsequently reported normal
typing. Do not describe the intermittent phone symptom as conclusively fixed
without a matched device reproduction. Flutter uses a SurfaceView here; the
trace did not expose Wing rows in the FrameTimeline table, so native `gfxinfo`
and other apps' jank classifications must not be substituted for Wing's frames.
See [Perfetto FrameTimeline documentation](https://perfetto.dev/docs/data-sources/frametimeline)
for the distinction between frame scheduling, submission and presentation.

## Workspace retention and membership regression boundary

```sh
flutter test test/project_membership_index_test.dart test/workspace_retention_test.dart test/profile_workspace_registry_test.dart test/profile_workspace_route_lease_test.dart test/chat_browser_data_test.dart
```

One connection/profile membership index uses stock `projects.tree`, inspected
at upstream commit `8d30c4e`. Its scan limit covers the complete session count
and is at least 5,000. The tree filters archived, child and some source sessions;
only an explicit Home membership proves that a chat is unassigned. An absent
key remains unavailable, including when coverage is incomplete. Browser tree
reads populate the same index. Profile refresh, connection loss, global session
changes and local project/session mutations invalidate it. The 100-project
regression requires one membership tree read across repeated assigned/Home opens
and no per-project membership scans; larger histories check the requested limit.

Each controller retains at most 20 unselected, unleased settled chat runtimes.
Selected and mounted-route chats remain owned, including routes covered by other
screens. Running turns, child/side work, input requests, drafts, attachments,
queues, mutations, recovery and notification delivery are exempt until they
settle. Separate retention notifications keep composer edits off workspace
monitoring updates. Cached disk reading snapshots retain their existing limits.
Evicted settled chats reload their server history on reopening.

The registry reconciles exact saved connection identities. Configured owners
remain available for connection status; deleted or superseded owners close only
after their leases settle. Network recovery first retires settled obsolete
owners, cancelling their idle recovery timers; recovery with pending work keeps
its owner. Network changes reconnect only remaining owners. Home removes obsolete cached
owner futures when saved connections refresh. Removed browser rows dispose their
notifiers after their last mounted listener detaches; a key that reappears while
still observed reuses its notifier.

The synthetic increasing-chat soak observes retained controller chat counts
and message-content code units; the connection-edit soak observes registry counts,
socket-close callbacks and reconnect request counts. These are executable
retention checks, not measured Dart heap bytes, phone PSS, frame latency or
battery results. Repeat the device matrix above before making those claims.
