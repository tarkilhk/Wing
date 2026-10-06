# Performance investigation

Measure the phone and Wing separately. A hot device can make Wing slow even
when another process supplies most of the sustained load. CPU use identifies
work; it does not measure an app's share of battery discharge.

Choose a concrete question before recording. Synthetic input can isolate a
regression such as draft edits rebuilding the transcript; it does not establish
ordinary product performance. Stop repeating a workload once that question is
answered. Use representative saved history, rich live responses, draft editing,
navigation and background recovery for real-use acceptance. An authorized live
run must use an owned QA chat and an explicitly verified model/reasoning route,
without changing existing chats or server defaults. Investigate a measured
failure or significant cost rather than expanding a generic benchmark suite.

## Measurement builds

Custom performance measurements are disabled by default. Explicitly enable them
in non-release builds with `--dart-define=WING_PERF_INSTRUMENTATION=true`.
`PerformanceInstrumentation.enabled` is a compile-time constant and is always
false in product/release mode, even if the opt-in flag is supplied. It gates
parser/request clocks, counters, completion event buffers and custom timeline
spans. Functional caches, worker scheduling and normal error reporting remain
active. Alternate Markdown benchmark renderers require the same opt-in; release
always uses background preparation.

Build the actual app with live observers using one command:

```sh
flutter build apk --profile --dart-define=WING_PERF_INSTRUMENTATION=true -t tools/performance/live_stream.dart
```

The profile package is `com.tarkilhk.wing.perfqa`. The live observer and replay
entry points are under `tools/performance/`; ordinary `lib/main.dart` does not
import them. Instrumented tools reject startup without the opt-in flag.
For offline streaming and typing, use `tools/performance/workspace_streaming_replay.dart`
as the target. Real model calls require an explicitly owned QA chat and an
explicitly verified Luna route; preserve connection/profile defaults.

Stock create/resume metadata does not establish reasoning effort. The live
observer reads it through `ProfileWorkspaceController.loadIntelligence`, which
uses session-scoped `config.get` with key `reasoning`, and requires `low` before
adoption or dispatch. This contract was inspected at upstream
`4787e4d56fc8d9265d4c7d3c0fe5accee86b4078` in
`tui_gateway/methods_session.py` and `tui_gateway/methods_config.py`.
Keep remote reasoning interpretation in this existing tested owner; inferring
it from arbitrary metadata cannot be established by a general static check.
The `workflow` mode requests a bounded Flutter change plan with a table and
code examples. Reuse an already-created owned QA chat after an uncertain setup;
never repeat creation merely because its client-side verification failed.

The replay's `prepareIdle` extension accepts histories of 2 or 50 rows. After
preparation, `startProbe` and `stopProbe` bracket 200 native draft edits and
report actual frame timings, transcript setup counts and workspace notifications.
Require enabled diagnostics, exact expected draft, unchanged geometry/focus,
settled history and zero transcript setup and workspace notifications.

For the offline navigation soak, build the same profile variant targeting
`tools/performance/workspace_navigation_soak.dart`. Its `ready` and `round`
extensions use the real workspace with synthetic 50-message chats. Use it when
investigating a specific retention regression. The extended workload supports
twenty `same` rounds and twenty `increasing` rounds; choose the duration needed
to distinguish expected cache growth from continuing retention. Record settled
heap/PSS alongside retained transcript and runtime counts. This fixture performs
no network I/O and cannot certify socket retention or live Hermes delivery.
Both offline fixtures keep preferences in memory.

Run parser, worker and rendering tests with measurements enabled:

```sh
flutter test --dart-define=WING_PERF_INSTRUMENTATION=true test/performance_instrumentation_test.dart test/markdown_inline_parser_test.dart test/markdown_parse_worker_test.dart test/background_markdown_content_test.dart test/background_markdown_message_test.dart
```

The same tests run without the flag to verify functional behavior with zero
measurement counters. For the standalone parser benchmark:

```sh
dart run -DWING_PERF_INSTRUMENTATION=true tools/performance/markdown_parse_benchmark.dart build/performance/parser.json
```

Release checks compile and execute the actual parser/worker in product mode,
deliberately requesting instrumentation and an alternate renderer:

```sh
mkdir -p build
dart compile exe -DWING_PERF_INSTRUMENTATION=true -DWING_QA_MARKDOWN_VARIANT=baseline tools/qa/check_release_instrumentation.dart -o build/release-instrumentation-probe
build/release-instrumentation-probe
```

`scripts/verify_release_apks.py` also inspects uncompressed app snapshots in every
release ABI for custom trace and test-RPC markers. Marker absence corroborates
the compile-time guards; it is not a universal proof about all possible overhead.

## Private evidence storage

Keep this document procedural. Do not commit recorded device/host measurements,
experiment logs, CPU samples, traces, screenshots or comparison reports. Capture
tools use ignored `build/` directories while running. Archive completed runs in
an owner-only directory outside this checkout, grouped by date, experiment and
**tested** commit, before removing temporary captures. Include workload, build
hashes, device configuration and relevant manifests with each archive. Clearly
label instrumented diagnostic results separately from ordinary-build timings.

Retain reusable scripts, synthetic fixtures and regression contracts here. Large
raw traces and APKs can use a shorter retention period than compact reports and
manifests. A local archive needs its own backup; keeping files outside Git alone
does not provide durability. Existing published history is unaffected by removing
reports from the current source tree.

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

Select the scenario that answers the measured problem or changed contract.
This matrix describes available investigations; it is not a command to run
every workload after every change. Set an observable stopping condition before
starting, and retain inconclusive evidence rather than repeating blindly.
Required program acceptance remains governed by its verification contracts.

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
The profile variant installs as `com.tarkilhk.wing.perfqa`, separate from release
connections and drafts. Configure an equivalent test connection/data set there.

```sh
flutter build apk --profile --dart-define=WING_PERF_INSTRUMENTATION=true -t tools/performance/chat_frames.dart
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

For a bounded ordinary-release scheduler trace or sparse screen-off battery
capture, use the separate runner:

```sh
python3 tools/qa/phone_performance_capture.py trace --serial <device> --seconds 45 --label stream-typing --output build/performance/stream-typing
python3 tools/qa/phone_performance_capture.py battery --serial <device> --seconds 1200 --expected-wing-state running --label background-settled --output build/performance/background-settled --abort-file build/performance/abort
```

The caller stages the workload and app state. The runner does not send prompts,
change settings, stop apps or reset battery statistics. Trace mode is bounded
to 60 seconds and retains its owned remote trace if pulling fails. Battery mode
reads charge, power and process state at 0/10/20 minutes; use a separate output
directory for every attempt. Charging, an observed lit screen or an unexpected
process state makes the arm inconclusive. Sparse checkpoints do not establish
continuous sleep, process retention or deep Doze. Keep phone interactions,
traces and continuous sampling outside quiet battery intervals. Compare both
ten-minute halves and record cooling/order effects in sequential comparisons.

`test/phone_luna_live_performance_test.dart` is opt-in. `PREPARE_WARMUP` creates
one owned chat and one tiny turn through an explicitly verified advertised Luna
route; `OBSERVE` attaches to that chat while the phone sends the measured turn.
The test documents its required environment settings and retains an attempt
manifest under ignored `build/`. Never retry an uncertain creation/submission
with the same nonce or use an inherited non-Luna default. It changes no profile
defaults. Observer timeout retains the chat without interrupting or deleting it.

Flutter frame-log batch timestamps are callback receipt times, not exact frame
times; bounds may straddle scenario transitions. Native presentation API calls
are submissions, not presented FPS. Missing Wing SurfaceView FrameTimeline rows
must be reported as missing coverage, not replaced with another app's jank data.

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

Text and reasoning deltas are accumulated immediately, with presentation bursts
coalesced at 100 ms. The first delta and phase/control/error/completion changes
publish immediately. `test/streaming_presentation_test.dart` checks those flush
boundaries, multiple-chat invalidation and disposal. The growing-text workload
also bounds live Markdown rebuild count and preserves exact final text and fresh
composer input. This reduces publication frequency; it does not bound the cost
of parsing, layout or semantics for an increasingly large live message.

Live prose also retains unchanged top-level Markdown blocks after parsing the
complete current document. Comparing resolved ASTs preserves reference/link
changes; replaced blocks release their recognizers. The message owns this cache
and rendering dependencies invalidate it. Fenced code keeps its existing
controls; documents with heading anchors use the stock renderer. The 1,200-word,
100-update regression retains 950 block widget/element identities and builds
100 new blocks. Selection survives growth from one paragraph to several.
`test/block_reusing_markdown_body_test.dart` covers stock layout parity,
reference changes, callbacks, theme/scale changes and disposal. Full-document
parsing and rebuilding a changing large single block remain costs to measure.

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

The work-budget test uses 2,400 synthetic messages and requires an event-loop
turn before the large save completes. Snapshot collection in the controller
still runs on the UI isolate and should be included in future CPU profiles.

Use matched device reproductions to validate intermittent slowdowns. Flutter
uses a SurfaceView here; absent Wing FrameTimeline rows cannot be replaced by
native `gfxinfo` or another app's jank classifications.
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
