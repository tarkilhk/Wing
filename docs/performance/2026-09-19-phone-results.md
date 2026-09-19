# Phone performance acceptance, 19 September 2026

Application source: `3cc7628` (includes latest fetched `origin/main`, `def56b2`).
The baseline is `def56b2` before the authentication/refresh fixes. Both were AOT
profile builds with the same benchmark entry point and ordinary Wing Dev signing.
Only measurement tooling changed during phone preparation; application code did not.

Device: Samsung SM-S918B, Android 16, 1080 × 2316, density 420. Real saved backend
connection, five profiles, dark theme, original filters and project grouping.
Renderer: Impeller Vulkan. Android confirmed 60 Hz for the controlled comparison;
the phone's original setting was 120 Hz and was restored after the core tests.
Battery temperature was 37.0°C initially and 38.4°C after the core sequence;
Android reported light thermal status (1), with no override. No builds, screen
recording or CPU sampling ran during the frame measurements.

## Controlled 60 Hz comparison

Each run is 30 seconds of warmed scrolling, including a pull-to-refresh. The
list returns to the top through the benchmark-only hook so setup gestures do
not cause extra refreshes. Both builds preserve the same viewport and preferences.

| Build / run | Frames | UI p95 / p99 (ms) | Raster p95 / p99 (ms) | UI frames >16 ms |
| --- | ---: | ---: | ---: | ---: |
| Baseline 1 | 1,775 | 3.738 / 14.060 | 2.897 / 3.560 | 12 |
| Baseline 2 | 1,796 | 3.582 / 4.307 | 2.967 / 3.451 | 1 |
| Baseline 3 | 1,769 | 3.645 / 13.574 | 3.031 / 3.777 | 12 |
| Candidate 1 | 1,794 | 3.667 / 4.654 | 3.137 / 3.681 | 5 |
| Candidate 2 | 1,818 | 3.836 / 4.477 | 3.235 / 3.846 | 0 |
| Candidate 3 | 1,799 | 3.655 / 4.600 | 3.107 / 3.774 | 6 |

**All three candidate runs pass UI and raster p95 <=16 ms and p99 <=32 ms.**
No raster frame exceeded 16 ms in either build. Typical AOT scrolling cost is
similar before and after; the candidate has fewer UI outliers (11/5,411 versus
25/5,340) and a lower worst-run UI p99. This short experiment does not establish
a universal speedup percentage. The earlier slow debug/JIT results cannot be
used as a same-mode comparison to claim that all the gain came from code changes.

## Refresh, scale and interaction checks

- Five consecutive awaited real refreshes: 1.967, 2.034, 1.912, 1.750 and 1.894
  seconds. Each returned Connected with five profiles, no active loading, and no
  visible profile or controller errors.
- Background/foreground recovery: Connected with no visible errors on the first
  successful observation, 47 ms after the foreground command completed. This is
  a readiness observation, not an exact time-to-first-pixel measurement.
- Status, Profile and Project filter menus each opened and closed correctly;
  selections were not changed.
- Expanded the 637-chat Home group and repeated a 30-second scroll/refresh run.
  1,813 frames: UI p95 4.213 ms, p99 5.168 ms; raster p95 3.036 ms, p99 3.495 ms.
  Six UI frames exceeded 16 ms, maximum 28.103 ms; no raster frame exceeded it.
  No extra chat-count limit is supported by these measurements.
- One observed launch per build reached confirmed index readiness after 6.138 s
  for baseline and 4.207 s for candidate. These include launch/VM observation and
  backend timing; they are not statistically repeated startup benchmarks.
- The baseline's login attempts were allowed to age out for 62 seconds before
  the candidate launched, preventing the known rate-limit bug from contaminating
  the candidate's authentication result.

The original five-refresh transport test and emulator HTTP measurements establish
shared authentication and no duplicated reads. These phone observations confirm
the installed client's user-visible reliability; they do not independently count
all network requests. See the [earlier investigation](2026-09-19-chat-browser.md)
for the request counts and regression coverage.

The automated core sequence completed in 376.6 seconds, including restoration of
normal Wing Dev 22672 and the original display settings. With the owner's explicit
allowance for more time, a separate follow-up checked the native 120 Hz setting.

## Native 120 Hz follow-up

Android confirmed 120 Hz with both refresh-rate preferences restored to their
original unset values. Candidate 22673 used the same application source and
benchmark entry point. Three additional warmed 30-second runs:

| Run | Frames | UI p95 / p99 (ms) | Raster p95 / p99 (ms) | UI frames >16 ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 3,608 | 2.639 / 3.399 | 2.352 / 2.819 | 3 |
| 2 | 3,573 | 2.676 / 3.363 | 2.426 / 2.914 | 0 |
| 3 | 3,597 | 2.613 / 3.337 | 2.374 / 2.861 | 5 |

Both thread p95 and p99 values are also below the tighter 8.33 ms native-refresh
budget. There were eight UI frames over 16 ms among 10,778 samples, including one
33.091 ms maximum; no raster frame exceeded 16 ms. This is not a zero-jank claim
or a measurement of input-to-display latency. There is no native-120 Hz baseline,
so these runs establish candidate performance, not a before/after speedup.

## Final restoration and evidence

Installed ordinary Wing Dev **22674**, AOT profile mode with `lib/main.dart`, in
place with app data preserved. APK inspection confirms no benchmark service
extension names or frame logger in the arm64 application library. That library
matches the earlier ordinary candidate 22672 byte for byte. The final screen
showed the approved Chats UI, green backend indicator and no loading errors.
Both refresh-rate preferences remained unset, as originally found. No chat was
sent, no filter selection changed, and production Wing was not modified.

The generic launcher-shortcut checker could not parse Samsung's redacted IDs and
intents. Direct inspection showed all three enabled manifest shortcuts and the
correct Dev activity; exact intent actions were not independently verified by
that phone dump. This is a verification limitation, not evidence of a shortcut
regression.

Final APK SHA-256:
`2d09e4c07784b54dfd6fd2931dae526184d18a740c20a751ccdc1abb0ad75f6b`.
The versioned LAN download and existing target download alias both point to it.

[Structured measurements](2026-09-19-phone-frames.json) retain all run percentiles,
maxima, counts, five refresh snapshots and restoration metadata, with the wireless
ADB address removed. Benchmark scripts passed Python compilation and the Dart
entry point passed static analysis; the application's 209 relevant tests were
already passing before this measurement-only work.

Physical-phone acceptance and emulator acceptance remain distinct: these results
do not mean that the software-rendered emulator passed its raster threshold.
