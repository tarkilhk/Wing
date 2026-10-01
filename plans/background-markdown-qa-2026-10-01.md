# Background Markdown QA — 2026-10-01

This experiment is on `perf/background-markdown`, based on `71af1fb`.
Production/main and the Hermes server are unchanged. The installed Android
candidate is **Wing Perf QA**, package `com.tarkilhk.wing.perfqa`, with the same
QA signing certificate and retained settings. Its existing Hermes connection
initialized successfully: seven profiles, Connected, no controller/loading/UI
errors. No model requests or new backend chats were made in this window.

## Changes and correctness

1. Reject non-backtick positions before the deliverable inline-code regex.
2. Cache exact unchanged inline expansions, including the document's link
   reference context. Reparse every block snapshot; parse footnote candidates
   fresh. Clone mutable ASTs and prune unused entries on each snapshot.
3. Parse chat prose on one reusable Dart isolate. Each body retains its last
   ready snapshot and coalesces updates behind one request. The shared worker
   serializes jobs and removes canceled queued work. It releases caches and
   stops when its last owner leaves or the app backgrounds.

The streaming-to-saved transition seeds the new body from an already displayed,
same-grammar source prefix. Only mounted streaming bodies can donate; snapshots
are cloned and no global history cache persists. Async publication captures the
visible changing row's reading position. Completion resolves the corresponding
saved-row anchor during layout while retaining the captured old position.
Activity tabs and local drafts remain mounted.

Independent review and regression tests caught and resolved stale-result
publication, incompatible AST reuse after a grammar change, lost reading
positions when final text includes unseen paragraphs, and activity-state resets
in an intermediate key-transfer implementation.

Validation: **2,686 full-suite tests passed, 17 existing opt-in tests skipped**
in the baseline comparison mode;
analysis with fatal infos is clean. Background parser/renderer tests cover
real-isolate transport, cancellation/startup disposal, coalescing, replacement,
pause/resume, error recovery, exact prefix AST parity, references/footnotes,
selection, callbacks, code controls, themes and enlarged text. Eight completion
scroll cases preserve the reading marker within 1 px. Both background and cache
transcript suites pass 25 tests, including retained tabs/draft/current callbacks.

## Measured results

Each phone replay contains 600 deltas, 60 publications and 120 programmatic draft
edits over six seconds. CPU sampling was disabled. All eight accepted runs
displayed the exact final message and draft with zero pending parses, stable
keyboard geometry/focus, and complete overlapping SurfaceFlinger ring coverage.
The display reported 120 Hz. Native gaps below are between actual presentations
inside the replay's monotonic bounds, not Flutter build durations.

**One valid pass per variant/workload**, not a repeated statistical comparison:

| Renderer | Prose build p95 | Prose displayed-gap p95 | Prose worst displayed gap | Mixed fenced build p95 |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 17.028 ms | 25.002 ms | 33.339 ms | 6.629 ms |
| Guard | 17.382 ms | 25.001 ms | 33.338 ms | 8.189 ms |
| Guard + cache | 8.026 ms | 16.671 ms | 25.009 ms | 7.930 ms |
| Guard + cache + worker | 3.760 ms | 16.665 ms | 33.332 ms | 7.565 ms |

The combined candidate reduced prose UI build p95 by 77.9%. Its prose build
maximum was 8.112 ms versus 24.814 ms. Mixed fenced messages did not improve:
build p95 increased by about 0.9 ms and native displayed-gap p95/worst stayed
approximately 16.7/25 ms. The guard alone showed no phone frame improvement.
The remaining 33 ms prose gap was not eliminated.

Combined-candidate final-render lag was 25.5 ms for prose and 76.0 ms for mixed
fenced content; final text caught up correctly. This bounded fixture observation
is not a general latency guarantee or a real IME-to-glyph measurement.

The separate host parser benchmark uses two warmups and seven measured repeats,
checking every snapshot's AST outside the timed interval. Median whole-document
parse totals across 60 publications were 593/526/77 ms for baseline/guard/cache
without fences and 692/642/84 ms with fences. Cache reduced roughly 6,350 inline
expansions to roughly 75. Host JIT timings exclude widget work, isolate transport
and phone/display latency; the smaller guard difference is noisy.

Two cold-start replay attempts failed setup checks and were excluded. The second
failure ended the planned reverse-order repeats so the phone could be released.
No parser crash or final-text failure was established by those setup rejections.
Phone settings were restored, the QA recent task removed, and production Wing
returned to the foreground with its APK hash unchanged. The improved QA APK
remains installed, SHA-256
`6f5c885e105315dcc5772f0a50f32fc615a55563563c7c4cd68686fb65812182`.

## Reproduction and remaining acceptance

`WING_QA_MARKDOWN_VARIANT` accepts exactly `baseline`, `guard`, `cache`, or
`background`. These are explicit experimental comparison modes, not a production
compatibility path. `background` includes all three changes. Profile builds on
this branch use the Perf QA identity; ordinary debug uses Wing Dev.

```sh
source ../.toolchain/env.sh
flutter test --no-pub --concurrency=8
flutter analyze --no-pub --fatal-infos
dart run tools/performance/markdown_parse_benchmark.dart
flutter build apk --profile --no-pub --split-per-abi \
  --target-platform android-arm64 -t tools/performance/chat_frames.dart \
  --dart-define=WING_QA_MARKDOWN_VARIANT=background
```

Build matched synthetic APKs by replacing the target with
`tools/performance/streaming_replay.dart` and choosing each variant. Uncompressed
APK payloads were verified to differ only in `libapp.so`, excluding signing
metadata. The prepared nine-APK kit and checksum manifest are under ignored
`build/background-markdown/artifacts/`. `tools/qa/replay_markdown.py` collects
frame timings and verifies final displayed content from the focused QA fixture;
it restores the VM profiler flag and exports no private service URLs/chat text.
Numeric phone summaries and cleanup evidence are under ignored
`build/background-markdown/phone/`.

The user authorized production promotion on 2026-10-01. Background parsing,
including the guard and inline cache, is now the default renderer; explicit
benchmark variants remain available for matched comparisons. Follow-up phone
testing will exercise real keyboard input during live Hermes streams using
**Luna only**, including long existing chats and mixed fenced messages. The QA
measurements above do not establish live-keyboard responsiveness, a new battery
result, or worker CPU attribution.
