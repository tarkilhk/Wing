# Physical-phone performance testing

The 30 September 2026 phone session is complete and control is released. The
Samsung S23 Ultra (Android 16) retains its application data, connection and
phone-exported backup. The app changes below are deployed and recorded in
commit `186f8bd`; QA tooling accompanies this report. These findings cover the completed
checks, without an overall readiness verdict.

## Scope and deployed artifacts

Wing remains a client for stock Hermes. The latest inspected upstream commit is
`f42f579cf8bac4918ac9599bece71618afadd846`, including the stock title-info/events
behavior. The deployed backend remains unchanged at `02e4118`, version 0.21.5.
No backend patch, plugin, custom endpoint or upgrade was introduced. Live turns
used the verified advertised `gpt-5.6-luna` / `openai-codex` route with low reasoning.

Production version 1.1.3/code 23562 was installed in place with the pinned signing
certificate and data preserved. Final verified deployment records are authoritative:

| Build | APK SHA-256 |
| --- | --- |
| Production | `c01562d434238bb260b48ec7831be970296cf00faef48bc8e35a66bad56b1de4` |
| Isolated `.perfqa` | `920a572ffc2dfd44f58bd26cd562184620c8e0d8e71e870a2aa49cc3ed332b03` |

The earlier production APK `e72e1955200f3e4258505d57bdc84fe8cc41251c248f9111bf56d3b6bd24e052`
remained unchanged across both battery arms. Recovery/block-reuse installs occurred
only after those intervals.

## Completed implementation and functional checks

- Submitted text is consumed before the first asynchronous preparation step.
  Immediate native typing survives send acknowledgement and stream completion.
  The final new draft also survived closing and reopening the route.
- Text deltas are ingested immediately; visible text updates are coalesced at
  100 ms. Control, phase, error and completion events remain immediate.
- Unchanged Markdown blocks retain widget/element identity. The host fixture
  retained 950 unchanged paragraphs and reduced 1,050 block builds to 100.
  Whole-document parsing remains; this structural result is not a phone speed claim.
- Outgoing work is persisted separately as paused recovery, retaining attachment
  bytes until acknowledgement and preserving fresh typing. A dispatch marker
  prevents uncertain automatic resends or unchanged queue-edit retries. The user
  approved retaining existing saved queues when adding that marker.
- Thirteen recovery regressions passed. Final host validation passed 2,651 tests,
  with 16 opt-in skips and no failures. Analysis of `lib test tools/performance`
  reported no issues; final source review found no blockers.
- Actual production activity re-entry passed three shortcut/launcher cycles and
  the notification route: original activity, one Wing task, no Flutter eviction.
- Production prose and composer controls were inspected in light/dark at normal
  and Extra Large (130%) text size without observed issues. Native word selection
  showed handles/menu; clipboard contents were not changed.

## Measured performance and limits

| Capture | Workload/coverage | Findings |
| --- | --- | --- |
| Sampler-disabled block-reuse profile stream | 116 native taps, 32.085 s, 3,341 engine timings | Approximate process CPU 73.46% of one core; build p95/p99/max 11.489/19.252/26.078 ms, raster p95 2.751 ms; 7.24% of builds >8.333 ms and 2.07% >16.667 ms. |
| Sampler-disabled settled typing + scroll | 112 taps then 12 swipes, 37.995 s, 881 engine timings | Approximate process CPU 16.40%; build p95 3.476 ms, raster p95 2.649 ms. Three long build records cluster near keyboard dismissal/scroll transition. |
| Complete block-reuse release scheduler trace | 119 taps; conservative covered interval 31.953536 s after trimming 186.464 ms | Total/main/raster CPU 78.901/37.653/19.728% of one core; longest main running slice 31.197 ms, 38 main slices ≥20 ms. Native submission interval p95/p99/max 19.258/28.260/49.014 ms. |
| Final a07 release surface-only capture | 118 taps, 32.184 s; central presentation core 19.151539 s | Approximate process CPU 71.93% of one core; 1,972 validated actual-present timestamps, interval p50/p95/p99/max 8.334/16.671/25.012/50.018 ms; 19 intervals ≥32 ms. |

The release trace parsed completely without data-loss counters; its configuration
warning concerns trace memory use. CPU scheduler slices are not Dart frame durations.
The separate endpoint CPU estimates have boundary-read/RPC timing uncertainty and
are not main/raster attribution.

The surface-only capture uniquely identifies production's owned BLAST SurfaceView,
uses the actual-present latency column, rejects invalid sentinels and excludes its
initial historical ring. Adjacent nonempty rings overlap with no observed ring
discontinuity. All samples defining the central core report an 8,333,333 ns period
(120 Hz context). Conservative central bounds reduce workload-edge ambiguity;
clock alignment assumes no suspend while awake and does not equate the native
presentation clock with uptime. This establishes observed layer cadence, not a
smooth-FPS verdict, classified jank or input-to-glyph latency. Native submissions
and actual presentations are different metrics. Earlier three-candidate surface
attempts were inconclusive and remain separate.

The a07 Luna turn completed with 2,092 chunks and 9,903 characters in 41.78 seconds,
without tools. These are whole-turn totals, not exact text progress inside the
shorter timing core. Generated content, pacing, histories, tap counts and observers
vary between runs; neither lower CPU nor shorter tails establish causal savings.

The residual bottleneck is growing live-response UI work. Current profile build
p95 rises from 3.572 ms in the first five-second callback window to 14.946 ms in the
last full window, and 16.492 ms in the final shorter window. The aggregate p95 is
shorter than an earlier 19.520 ms capture but still exceeds the theoretical 120 Hz
budget. Whole parsing, layout and semantics are source leads; current lightweight
captures contain no stacks that precisely apportion their costs. Frame callbacks
are batched, phase boundaries are approximate and late callbacks can be excluded.
The settled mixed run has no per-phase CPU or exact typing/scroll timestamps.

## Battery result and scheduling error

The 13:14:47–13:34:47 UTC stopped-app arm passed sampled checks: **69.30 mAh over
1,200.045 s**, approximately **207.89 mA whole-phone discharge**. Its ten-minute
rates were 221.72 and 194.06 mA; temperature fell 34.0→32.9→32.7°C, SOC 43→42→41%.

The 13:37:14–13:57:14 UTC running arm is **inconclusive**: the final checkpoint was
Awake/screen-on. PID 330 was stable at sampled checkpoints and charging was absent,
but its 97.02 mAh counter drop includes screen-off and awake time. It cannot estimate
background Wing drain or be compared as a valid full screen-off arm.

The user left the screen off for the requested 40+ minutes. Our 146.501-second
setup gap extended the schedule to 42 minutes 26.582 seconds. Later PowerManager
last-wake reason 1 (stock Android power button) and conditional host/uptime mapping
place the wake about 101.065 seconds before the endpoint: 18 minutes 18.972 seconds
after the running arm began and 40 minutes 45.518 seconds after the first arm began.
This is consistent with the user's wait; our schedule overran it. The reason field
does not identify who or what pressed the button. Mapping assumes no suspend since
that wake; sparse checkpoints do not prove continuous earlier screen-off state.

No counter was sampled at wake, so removing awake time from the denominator cannot
recover an off-only rate. One later privacy-filtered history query recognized zero
rows and recovered no near-wake counter; this does not prove history was absent.
No raw history/identities/event text was saved. Older awake/aborted attempts are
retained separately and are not valid pair evidence.

There is no valid full-arm running-minus-stopped estimate or app-attributed energy
result. Cooling/order, AOD/idle policy, wireless ADB, background services and gauge
reporting confound even a valid sequential pair. Observed counters are multiples
of 4.62 mAh, a reporting pattern rather than a verified resolution/error bound.
The first running ten-minute prefix is descriptive only. No additional long pair
or automatic restart was undertaken.

## Restored phone and remaining coverage

### 1 October screen-off battery follow-up

The requested fresh comparison completed on the same phone using the installed
production Wing 1.1.3/code 23562, unchanged across both arms. Earlier interrupted
attempts were excluded. The user followed progress from a laptop and was released
only after the final counter and screen-state readings were saved.

| Condition | Singapore time | Charge lost | Whole-phone mean | Ten-minute means |
| --- | --- | --- | --- | --- |
| Wing stopped | 15:08:49–15:28:49 | 55.44 mAh / 1,200.042 s | 166.31 mA | 221.75 / 110.88 mA |
| Wing idle in background | 15:31:49–15:51:49 | 41.58 mAh / 1,200.034 s | 124.74 mA | 55.43 / 194.05 mA |

Both arms passed all sampled validity checks: unplugged/discharging, Dozing,
device-idle screen off; Wing absent throughout stopped checkpoints and PID 29652
unchanged throughout running checkpoints. QA was stopped. No profiling, test
messages or synthetic input ran during either interval. Setup briefly woke the
screen outside both arms, followed by sleep and settling before the running arm.
The counter midpoint setup gap was 179.519 seconds, making the pair span
42 minutes 59.594 seconds. Running preflight/postflight last-wake and last-sleep
markers were unchanged. No settings or application data were changed.

Running-minus-stopped observed discharge was −13.86 mAh, or −41.58 mA (about
25.0% lower). **No added idle drain was observed in this pair.** This does not
establish a Wing battery improvement or isolate its energy use. Stopped
temperature fell 32.3→31.3→30.6°C, running 30.7→30.3→30.2°C; deep-idle policy
differed, and ten-minute rates varied substantially. This is one sequential
whole-phone comparison with sparse wireless-ADB observations, not repeated,
randomized app-energy measurement or a bound on smaller/intermittent drain.

Independent host recomputation agreed with both total rates, halves and timing.
Reports are retained under ignored `build/phone-performance/run-20261001-attempt4/`:
`comparison.md`, `comparison.json`, both `battery-*/capture.json`, `transition.json`
and running preflight/postflight records. The required fresh full screen-off pair
is complete; no further phone-control interval is running.

### September restoration and broader coverage

`final-phone-cleanup.json` verifies original rotation settings restored exactly
(accelerometer rotation 1, user rotation 0), Dark/Default appearance restored,
QA force-stopped, QA zero / production one task and no cleared application data.
The two Recents cards were QA plus production, not duplicate production tasks.
Successful cleanup was the final uniquely owned QA root-stack removal; the earlier
activity-flag attempt did not remove it. Phone control is released.

Owned temporary credentials, backup passphrase and host backup copy were removed.
The phone-exported backup and user files/data were preserved.

Completed current gates are host validation/review, signed in-place deployment,
stream/fresh-draft checks, activity re-entry, physical render/selection inspection,
owned-layer presentation analysis, restoration and the 1 October full battery
comparison. Broader coverage still absent: repeated battery comparisons,
a 20-minute native navigation soak and measured input-to-presentation latency.
These require a later user-arranged window; no overall readiness conclusion or
new phone-control interval is implied.

## 1 October streaming follow-up: retaining unchanged segments

A matched profile replay isolates the production `ProfileMessage` renderer and
simultaneous composer updates without app storage, backend traffic or model calls.
Both APKs use the same fixture, package, certificate and native configuration;
their only differing archive entry is `lib/arm64-v8a/libapp.so`. The baseline
renderer is exactly commit `1f6120c`. The candidate retains unchanged complete
code/prose segments, including their inherited wrappers. Theme, text scale,
viewport and renderer configuration still invalidate rendering. Document previews
retain full traversal for heading anchors; changing prose still gets a full parse.

Each replay requests 600 deltas, 60 publications and 120 programmatic draft edits
over six seconds. Keyboard, foreground, geometry, animation and final-state checks
must pass. An active production shimmer requests continuous frames. This is a
technical Markdown stress fixture, including identifiers with underscores, rather
than a representative sample of every conversation. Draft edits exercise composer
rendering, not physical IME input-to-presentation latency.

Three valid repetitions per renderer and workload had full native interior ring
coverage with overlapping polls at a reported 120 Hz. Native intervals require
both endpoints within actual monotonic replay bounds trimmed 500 ms at each end.

| Workload / renderer | Build p95 across three runs (ms) | Native interval p95 (ms) | Native maximum interval (ms) |
| --- | --- | --- | --- |
| Mixed Markdown / baseline | 12.803, 13.714, 10.547 | 24.998, 16.674, 16.671 | 25.012, 25.009, 25.009 |
| Mixed Markdown / segment reuse | 8.259, 8.167, 5.456 | 16.670, 16.671, 16.668 | 33.335, 25.006, 16.674 |
| Prose / baseline | 23.152, 22.466, 24.387 | 33.329, 25.007, 33.335 | 41.671, 41.682, 41.673 |
| Prose / segment reuse | 21.100, 23.465, 21.969 | 25.007, 33.334, 25.013 | 41.680, 41.675, 33.344 |

Returning to the baseline after the candidate restored mixed build p95 to
12.660 ms, with native p95 24.997 ms and maximum 33.333 ms. Two earlier return
attempts failed before capture and remain excluded, rather than counted as clean
runs. A CPU-stack diagnostic failed while retrieving samples through an obsolete RPC;
no CPU attribution is established by it. Mixed build cost improves, but native
worst-case gaps are not consistently lower and prose-only cost remains unresolved.

SurfaceFlinger rows describe layer presentation intervals. Upstream source
establishes compatible monotonic clocks; OEM fence accuracy, possible legacy
presentation estimates, complete physical refresh observation and correspondence
to individual Flutter frames remain unproven. Polling and run order can affect
results. No comparison with September's generated Luna responses is causal.

The original QA APK was restored in place, its data preserved, its process stopped,
and no QA Recents entry remained. Production was unchanged during this comparison
and phone control was released. Ignored artifacts are retained under
`build/streaming-performance-20261001/`, including numeric phone captures,
`phone-summary.json`, matched APK hashes and `timing-sources.md`.

### Remaining prose work: attachment syntax prechecks

`ProfileMessage` enables deliverable rendering. Its MEDIA and plain HTML-path
syntaxes previously attempted a regular expression at every candidate inline
position, including ordinary words and identifiers. Necessary first-character
checks now reject impossible starts before the regex; match positions, regex
grammar, conversion, Markdown precedence and complete-document parsing remain
unchanged. No prefix parsing, background parser or backend change was added.

The new structural regression first failed with 1,407 ordinary-text and 3,799
technical-text MEDIA probes. Both fixtures now require zero underlying MEDIA and
HTML-path regex probes. Seven focused tests pass, including exact deliverable
attributes, every unfinished positive prefix, quoted/space-containing paths,
reference links, footnotes, table/list content, Unicode/surrogate boundaries,
explicit match positions and EOF. Independent source review found no blockers.

An alternating-order host JIT diagnostic uses all four production deliverable
syntaxes at the same 60 no-fence publication positions. All 180 resolved ASTs
matched the original unguarded oracle. Total parse time fell by 10.3%, 12.2% and
13.4% across three rounds. These local diagnostics do not establish phone latency;
the earlier whole-widget host benchmark omitted deliverable syntaxes and must not
be used to attribute this particular cost. Reports and the probe script are under
ignored `build/streaming-performance-20261001/deliverable-*`.

Final host validation for both fixes passed 2,666 tests, with 17 opt-in skips,
and static analysis of `lib test tools/performance` reported no issues. Format
and whitespace checks passed. Both the matched profile fixture and ordinary
production release built successfully; signing certificates match the existing
QA and production installations. The fixture is profile-only and is not the
production entry point. Source hashes and APK hashes are retained with the
ignored artifacts. A release attempt using stale generated test-plugin
registration failed; rerunning normal Flutter release generation succeeded.

### Combined-fix phone comparison

A second user-arranged window collected three fresh baseline and combined-fix
runs per workload, followed by one baseline-return run per workload. All 14 runs
passed workload, keyboard, geometry, foreground, animation, exact-state, clock
and full native-interior coverage checks, at a reported 120 Hz. Matched APKs again
differ only in `libapp.so`; the fixture and native configuration are unchanged.

| Workload / renderer | Build p95 across three runs (ms) | Native interval p95 (ms) | Native maximum interval (ms) |
| --- | --- | --- | --- |
| Mixed Markdown / baseline | 13.295, 14.245, 12.899 | 16.676, 24.999, 16.673 | 25.008, 33.344, 33.345 |
| Mixed Markdown / both fixes | 7.378, 7.798, 7.687 | 16.672, 16.670, 16.670 | 25.010, 25.006, 25.001 |
| Prose / baseline | 23.465, 24.671, 24.016 | 33.333, 33.337, 33.337 | 41.686, 41.678, 41.688 |
| Prose / both fixes | 15.444, 21.528, 23.009 | 24.999, 25.005, 33.333 | 25.005, 33.341, 41.668 |

Mixed build-p95 median fell 42.2% (13.295→7.687 ms), with all three fixed runs
below all three initial baseline runs. Returning to the baseline restored mixed
build p95 to 13.164 ms, native p95 16.673 ms and maximum 33.334 ms. This supports
the repeated mixed rendering-cost reduction. Native p95 was usually already
16.67 ms, so it is not evidence of a general increase to 120 presented frames/sec.

Prose's median build p95 was 10.4% lower (24.016→21.528 ms), but the improvement
shrank across runs. The returned original prose renderer measured build p95
21.563 ms, native p95 25.007 ms and maximum 33.344 ms, similar to the middle fixed
run. Consequently the phone result does not isolate a durable prose speedup.
The three initial prose cores had 84 intervals ≥32 ms over 15.105 s, compared with
40 over 15.123 s with both fixes; this is an observed series difference, subject
to order/background/temperature variation, rather than proof of causality.

All preflight charging flags were false. Temperature was 32.8–33.0°C before
baseline runs and 33.3–34.1°C before fixed runs. Independent host review agreed
with validity and the narrower conclusions. No interval ≥50 ms occurred in
either arm; the original September 50 ms symptom was not reproduced by this
fixture. One fixed prose run still reached 41.668 ms, and whole-prose parsing
remains. These changes reduce rendering work without an all-clear performance
or actual IME-latency verdict.

Numeric results are retained in ignored `window2-summary.json` and
`phone/window2-*/`, including per-run preflight records. The final signed
production APK is `8d6ebe38af428b8dd9043a119b6ff333ec52559c33d13076e1831c974890ec37`;
the deployment/restoration checkpoint is recorded separately after installation.

The changes were committed and pushed as `d04ade5` before installation. The final
release was then installed in place. Pulling only its installed base APK confirmed
the exact signed artifact hash above. Production was running with one Wing task;
the original QA APK was restored, QA stopped and no QA Recents entry remained.
Application data, phone backup and system settings were preserved. The screen had
automatically slept during installation/postflight; no final screen-on production
UI inspection is claimed. Phone control was released immediately after these
checks. `deployment-final.json` retains the numeric checkpoint. CI status is
tracked separately from the successful local validation.

## CPU attribution preparation (2026-10-01)

`tools/qa/trace_streaming_cpu.py` records bounded `getCpuSamples` and Dart,
Embedder and GC timeline events from the existing synthetic profile replay. It
requires the QA package to be focused and the replay extension to be present,
checks replay/keyboard/geometry/frame validity, and restores the original profiler
and timeline-stream settings with read-back. CPU samples use the exact replay
monotonic bounds; the timeline envelope includes both replay markers. Per-frame
build/raster durations and build-start timestamps allow slow-frame stack analysis.
Function table indices retain leaf-first stack order. Timeline arguments,
metadata, service URLs and private script URLs are excluded from exported reports.

The earlier ad hoc diagnostic called an obsolete RPC while retrieving samples.
The replacement uses the supported `getCpuSamples` RPC. Direct HTTP stream-list
parameters use the VM enum-list format (`[Dart,Embedder,GC]`), verified against the
[Dart VM implementation](https://github.com/dart-lang/sdk/blob/main/runtime/vm/service.cc).

Eleven focused host tests pass, covering protocol encoding, sample/clock bounds,
redaction, replay validity and setting restoration on both success and failure.
An Android API 36 x86_64 emulator ran the actual AOT profile APK: both plain and
mixed replays completed with CPU samples, frame events and restored settings.
These runs validate capture functionality; emulator timings do not establish
phone performance or explain the phone's residual 41.668 ms presentation gap.
Ignored validation artifacts are in `build/cpu-trace-20261001/`.

Next phone window: budget about 10 minutes with the phone unlocked, screen on,
unplugged and idle. Install the prepared ARM64 replay APK into the existing QA
package, enable profiling and the buffered timeline through launch extras, then
record two prose runs and one mixed run. Stop early if a capture precondition
fails rather than repeatedly consuming the phone window. Restore the saved QA
APK in place, stop QA and remove only its Recents task, then release the phone.
Production data and settings must remain intact. The replay uses synthetic text,
so no Hermes model requests or backend tokens are needed.

After releasing the phone, correlate CPU stacks with the slowest build intervals
and inspect parsing, widget rebuilding, layout and GC. CPU sampling adds overhead;
these recordings identify likely costs rather than measure an unprofiled speedup.
Dart sampling does not provide complete native scheduling/GPU attribution. If
those remain unexplained, report that limit before proposing an additional trace.

## Evidence

Ignored reports under `build/phone-performance/run-20260930/`:

- `qa-block-reuse-light-stream/analysis.md` and numeric summary.
- `qa-block-reuse-settled-scroll/analysis.md` and numeric summary.
- `release-block-reuse-stream/analysis.md` and trace integrity/SQL results.
- `release-present-stream/analysis.md` and `present-analysis.json`.
- `battery-manual-pair-analysis.md`, `battery-wake-inference.json`,
  `battery-history-primary-sources.md`, `battery-history-filtered.json`.
- Final verified release/profile deployment records, `final-phone-cleanup.json`
  and authoritative `recents-qa-final-removal.json`.

Rendered evidence is under `build/phone-performance/preparation/production-*.png`,
including prose light/normal, light/dark enlarged, word selection, a07 completion/
reopen and restored appearance. Production re-entry is recorded in root's
`release-final-activity-reentry.log`. `recents-qa-cleanup.json` records the earlier
failed flag attempt, not final cleanup success. Temporary credentials remain private;
backup/bootstrap setup must not be repeated.
