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

## Phone CPU attribution (2026-10-01)

The prepared ARM64 replay APK was installed into QA without clearing data. Two
prose replays and one mixed-fence replay passed all capture checks. They recorded
600 deltas, 60 publications and 120 programmatic draft edits each, with 2,835,
2,797 and 2,495 CPU samples respectively. Frame/CPU/timeline clocks overlap in the
replay bounds. Twelve focused recorder tests now pass.

The first attempted export was rejected because one sample had an empty stack.
The phone legitimately returns occasional samples without an attributable stack;
the recorder now retains and explicitly counts these, requiring at least one
usable stack. The successful captures have 2, 4 and 5 unattributed samples. The
initial attempt is excluded from the following results. The correction affects
host diagnostics only, not production rendering.

| Profiled workload | Build p95 / maximum (ms) | Raster p95 / maximum (ms) | Builds >16.667 / >25 ms |
| --- | --- | --- | --- |
| Prose 1 | 22.817 / 32.650 | 2.353 / 3.722 | 50 / 13 of 512 |
| Prose 2 | 21.656 / 29.435 | 2.444 / 2.896 | 45 / 10 of 521 |
| Mixed fences | 8.087 / 16.497 | 2.601 / 4.039 | 0 / 0 of 581 |

The worst prose frames spent 28.414 and 26.523 ms inside the Flutter BUILD
stage, versus 1.826 and 0.820 ms in LAYOUT, and 1.508 and 1.284 ms in PAINT.
BUILD therefore accounts for roughly 87% and 90% of their UI-frame wall time.
These stage durations include possible scheduling delays and are not function
CPU time. Repeated recognizable stacks run through `parseLines`, `parseLineList`,
`_parseInlineContent`, `parseInline`, `parse`, `tryMatch` and `matchAsPrefix`.
In frames above 25 ms, those parser chains occur in 106/346 and 77/260 observed
samples. Separate native regex-interpreter leaves occur in another 91/346 and
70/260 samples. These disjoint raw-stack observations are not exact elapsed CPU
percentages, and native singleton stacks do not identify a particular syntax.

The native offsets were symbolized offline using the unstripped profile engine.
The captured replay APK's `libflutter.so` and the local engine have the same ELF
Build ID `123f4485b6d2b0ffa3fcee77fdd1639e1bae52cc`. The recurring native leaves
resolve to Dart's `RawMatch` regex interpreter in `regexp-interpreter.cc`.
This supports regex execution as a substantial hotspot, without attributing it
to a specific custom syntax or Markdown feature.

No primary UI `CollectNewGeneration` or `CollectOldGeneration` pause overlapped
a slow build interval in either prose replay. Background GC and idle notification
events are distinct from UI pauses. AST signatures and text layout have much
fewer recognizable samples than the parser. This does not rule out their cost
in other workloads. Strict per-thread timeline B/E pairing had no mismatched
ends or negative durations; spans crossing the capture boundary are excluded
from complete-span claims. Source URIs are absent and names unqualified in this
AOT profile; attribution uses call chains and verified native offsets. VM function
ticks differ from recomputed raw-stack counts, so conclusions use the latter.

`BlockReusingMarkdownBody` still parses the entire growing prose document before
reusing unchanged resolved widgets. Code fences divide prose into smaller retained
segments, consistent with the mixed workload's lower parser cost. This comparison
uses different inputs and is not a causal optimization experiment. The next target
is full-prose inline parsing and repeated regex matching, preserving links, late
reference definitions, tables and Markdown formatting. Naively freezing an earlier
AST can produce stale content when later text changes its meaning.

CPU/timeline profiling adds overhead. This window measures UI stages and sampled
functions; it does not measure native presented-frame gaps, real IME latency,
a battery baseline or an unprofiled improvement. The prior 41.668 ms presentation
interval is not a measured 41.668 ms function call. These traces explain the leading
workload cost but do not establish all costs behind every display gap.

Phone control lasted about seven minutes from preflight to verified restoration.
The original QA APK was restored with its exact SHA-256, QA stopped and its unique
empty Recents root removed. Production's SHA-256 was unchanged, one production
task remained, and production was focused. The temporary screen timeout was
restored to 30 seconds; no app data was cleared. Battery readings were unplugged
at both endpoints and temperature rose from 33.4 to 34.9°C. The phone was released
before offline analysis. Numeric captures, independent analysis, root validation
and restoration evidence are retained in ignored `build/cpu-trace-20261001/phone/`.

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

## 2 October: answer renderer retention, live phone comparison

The completion-retention fix was compared against the pre-fix diagnostic APK on
the S23 Ultra. Both signed `.perfqa` APKs have identical non-signature archive
entries except `lib/arm64-v8a/libapp.so`. Each used the same mixed-format prompt,
one verified `gpt-5.6-luna` response, the same completion diagnostics and CPU
sampler, and 35 seconds of native SwiftKey typing during streaming. No backend,
profile defaults, production application or application data were changed.

The comparison window begins at the controller's synchronous completion handoff
and ends 500 ms later. Quantiles use nearest rank.

| Metric | Before | Retained renderer |
| --- | ---: | ---: |
| UI build maximum, completion window | 69.600 ms | 9.082 ms |
| UI build p95, completion window | 47.282 ms | 7.662 ms |
| Completion-window UI builds >16.667 ms | 4 | 0 |
| Message initializations / disposals | 4 / 4 | 0 / 0 |
| Background Markdown initializations / disposals | 32 / 32 | 0 / 0 |
| Code block initializations / disposals | 28 / 28 | 0 / 0 |
| Streaming-only UI build p99 | 11.529 ms | 11.633 ms |
| Whole-capture UI build maximum | 69.600 ms | 26.018 ms |

Baseline slow frames contain nested widget construction during layout. In the
matched completion window, CPU samples whose stacks include mount/inflateWidget
fell 70→2, and flushLayout 72→22. These sampled stacks overlap and are not additive
CPU-time attribution. The candidate records streaming-status updates with unchanged
text/configuration, nine cached block updates, and no new background parse requests.
This directly supports retaining the existing renderer at completion.

Responses differ in length (10,552→10,858 characters) and segment count (15→17);
this single generated pair does not establish a general streaming p99 improvement.
The observer also costs time: these are diagnostic profile measurements, not a
release benchmark. UI build durations are distinct from physical frame gaps.
SurfaceFlinger reported both 120 Hz and 60 Hz periods in both captures; observation
coverage differs, so their maximum gaps are not used as a causal comparison.

The completed answer and nonempty fresh draft were retained. Five settled scroll
gestures preserved the draft; native selection showed handles/menu, and code wrapping
worked and was toggled back. The live draft marker was recorded after typing, so
exact acknowledgement/completion text preservation remains covered by the regression
tests rather than an independently marked live boundary assertion.

The original regular QA APK was restored without clearing data, then stopped;
the uniquely verified QA root task was removed from Recents. Production remained
unchanged and the phone was released. Numeric traces, APK checks, rendered functional
evidence and `phone-restoration.json` are under ignored
`build/draft-outbox-phone-20261002/retention-phone-20261002/`;
`comparison.json` records the calculation, validity limits and restoration.

### Remaining streaming tail: offline trace investigation

No additional phone or backend access was used. Candidate streaming has 36 UI
frames in the 11.633–16.667 ms band and four above it (18.668–26.018 ms). Their CPU
samples show widget update/mount work, layout and platform-message calls; no
observer tree walk, incoming-message handler, draft-persistence path or main-isolate
full Markdown parser appears inside those sampled slow frame bodies. Observer work
does occur elsewhere, so this does not establish its lack of influence on the run.

The four worst frames' measured Markdown block construction is only 309–400 µs.
Platform-message stacks include `Clipboard.hasStrings`, Live Text availability and
text-action discovery, reached through selectable-text initialization. The installed
`flutter_markdown` 0.7.7+1 builder assigns a fresh `UniqueKey` to built prose text.
Wing retains unchanged blocks, but each changed paragraph rebuild therefore creates
new selectable-text state rather than updating the existing state.

A host-only probe confirmed the pattern through the production Markdown component:
five growing-paragraph snapshots retain the fixed sibling state, replace the growing
state on every subsequent snapshot, and each replacement adds one clipboard-status,
Live Text availability and process-text-actions call. This proves lifecycle churn,
not a phone timing improvement. Keeping the growing paragraph's selectable-text
state while updating its spans is the first concrete implementation target; native
selection, link targets, equal-text distinct paragraphs and structure changes need
explicit regressions.

Other slow frames also have broader rebuild/layout costs. One retained late-stream
16.247 ms frame has 12.469 ms of layout with a cached Markdown message and no GC
overlap. The Timeline ring retains only the final 2.432 seconds of streaming, missing
all four worst frames, and many CPU stacks truncate at 128 frames. Exact per-category
time requires a shorter capture with earlier Timeline retrieval and deeper stacks;
the sampled categories overlap and must not be summed. Evidence, probe source/output
and limitations are in `streaming-hotspot-analysis.json` beside `comparison.json`.

### Growing-paragraph implementation prepared for QA

`retained_markdown_paragraph.dart` now adapts the stock paragraph builder's
Column/Padding/Wrap output, retaining its selectable text controls while accepting
the current spans, styles and callbacks. It preserves opaque inline widgets and
custom paragraph ownership; Markdown parsing and grammar transitions remain intact.
Valid append-only selections are restored after Flutter updates its private
controller, with guards for focus loss, newer selections, superseded spans and disposal.
Ordinary streaming updates require no selection-related widget-tree traversal.

Twelve new regressions cover State/EditableText retention, elimination of repeated
native initialization calls, active selection, current link targets, repeated text,
grammar transitions, theme/scale, rewriting/removal, focus races and custom content.
The full project suite passes **2,748 tests**, with **17 opt-in skips**, and analysis
reports no issues. Two independent reviews found no remaining actionable issues.

The comparison baseline is `artifacts/retained-answer-diagnostic.apk`, including
the already measured completion fix. Prepared candidates are
`artifacts/retained-paragraph-diagnostic.apk` and
`artifacts/retained-paragraph-normal.apk` under
`build/draft-outbox-phone-20261002/`. The latter uses the ordinary application entry
point without the live observer or opt-in completion diagnostics. Both target the
isolated QA package. No phone/backend access or deployment was performed during
implementation. Actual streaming p99 improvement awaits the user's next test window;
`growing-paragraph-build-plan.json` records artifact hashes and final readiness.

### Growing-paragraph physical comparison, 2026-10-02

With the user's phone window, compared the retained-answer diagnostic baseline
against the retained-paragraph diagnostic candidate in place in `.perfqa`.
Both used one stock Hermes `gpt-5.6-luna` mixed-format answer, 35 seconds of
native SwiftKey input, identical CPU/frame observers, and sanitized Timeline
retrieval every two seconds. The periodic retrieval preserves the slow frames
that the earlier end-only Timeline ring had lost. Production was unchanged.

| Streaming-only UI metric | Baseline | Paragraph fix |
| --- | ---: | ---: |
| Frames | 1,678 | 4,452 |
| p95 | 7.079 ms | 7.213 ms |
| p99 | 10.567 ms | 12.054 ms |
| Maximum | 40.127 ms | 43.639 ms |
| Frames above 16.667 ms | 4 | 5 |
| Observed streaming duration | 16.983 s | 44.663 s |
| Final answer characters | 11,626 | 12,376 |
| Native typing keys | 139 | 145 |

This pair does **not** demonstrate a streaming p99 improvement. Live generation
duration, update count and content differ. The candidate diagnostics ring drops
626 early events; cumulative counters, CPU samples and periodically retrieved
Timeline data remain available, but retained event lists do not describe the
entire candidate capture.

Samples containing both native text queries and `initState` fall from 69 to 57
despite 364 versus 830 observed source changes. Their sampled density falls from
0.190 to 0.069 per source change. Native queries remain, especially `hasStrings`
associated with `didUpdateWidget`. These overlapping samples establish neither
call counts nor additive CPU time; host regressions independently demonstrate
that an appending stock paragraph no longer replaces its text-control State.

The baseline 40.127 ms frame spends 39.410 ms in PAINT. Candidate 40.729 and
43.639 ms frames spend 39.916 and 42.087 ms in PAINT respectively, with little
layout work. Each has only one or two CPU samples, no overlapping UI GC event
and no nested native paint spans. Existing traces cannot distinguish a blocked
thread, scheduling delay or unsampled native work. An Android system trace is
the next useful way to identify that delay; another speculative Markdown change
is not justified by these maxima. Completion retention still has no lifecycle
initialization/disposal in either arm's 500 ms handoff window.

Both turns finish and render their sentinel without chat errors. The candidate's
exact 145-character draft is marked while busy and survives completion; baseline
marking occurs after completion and does not independently prove that boundary.
Both SurfaceFlinger observers report an 8.333 ms period (120 Hz). Their full
35-second presentation-gap distributions are not a causal speed comparison:
baseline includes considerable time after generation finishes, when the app
does not need to present continuously. A refresh period is not proof that every
frame is presented on time.

Installed the ordinary fixed QA entry point afterward and verified the live
measurement extensions are absent. After correcting an initial search-box
navigation mistake, an owned synthetic QA conversation passes native composer
input (32 added characters), native text selection with Copy/Select all/Share
actions, and seven history scroll gestures. Code-wrap controls are not encountered
in this older synthetic conversation and are not claimed as exercised in this
ordinary-app pass. Previously measured code-wrap checks and host regressions
remain separate evidence.

The ordinary fixed QA build remains installed, force-stopped, with its one
verified recent-app task removed. Both profiler settings are restored; no
production app or unrelated task is changed. The phone reports no thermal
throttling and is released to the user. Sanitized evidence, screenshots of owned
QA content, comparison limits and cleanup verification are under ignored
`build/draft-outbox-phone-20261002/growing-paragraph-phone-20261002/`.

### Further offline analysis of the paragraph comparison

No additional phone/backend access or code changes were needed. Equal initial
17-second windows have p99 10.567 versus 10.357 ms, but do not match generated
content: the candidate has only about 4,011 characters at that point, while the
baseline answer is complete. The candidate's final 10 seconds instead have p99
14.114 ms and 49 frames above 10 ms, versus 11.192 ms and 16 in the baseline's
final 10 seconds. Source-size bins likewise do not match formatting, but show
similar p99 at 4,000–8,000 characters (11.658 versus 11.771 ms) and a larger
difference at 8,000–12,000 (10.334 versus 14.114 ms).

The expensive candidate tail contains a more complex mixed-format answer:
Markdown grows from 13 to 19 segments versus 4 to 13 for the baseline, ending
with nine versus six code blocks. Of the candidate's final 49 frames above 10 ms,
48 contain message rendering work and none contains a prose block build event.
Its draft is constant at 145 characters for the last 9.370 seconds; continued
typing is therefore not necessary for these expensive frames. Median message
build duration in the final 10 seconds is 712.5 us versus 461 us. Fence splitting
averages 838 us versus 494 us and peaks at 1.675 ms versus 1.217 ms, still far
shorter than the overall expensive frames.

Candidate 10–16.667 ms frames spend about two thirds of their traced time in
LAYOUT, which includes nested child builds in Flutter's lazy list; nested BUILD
must not be added again. This identifies broad widget update/layout work as the
remaining p99 path, not repeated prose AST/block construction alone. The whole
answer is one transcript row containing its prose/code segment Column. Cached
segment widgets avoid reparsing unchanged blocks, but do not by themselves remove
all ancestor rebuilding or layout as that row grows. Layout-boundary attribution
should precede a structural optimization.

The larger `hasStrings` sample count is not evidence that retaining a paragraph
moves clipboard work into its updates. The pinned Flutter source's
EditableText.didUpdateWidget clipboard check requires pasteEnabled, which is
false when readOnly; SelectableText sets readOnly=true. The composer is editable
and is reconstructed by the outer workspace listener even with its nested
composerChanges listener. CPU function names omit instance identity, so exact
editable-widget ownership is not proven. The source establishes a useful seam
for measuring redundant composer rebuilds without disabling selection features.

The diagnostic observer itself walks the mounted widget tree: source polling
every 20 ms locates the controller, and readiness polling every 100 ms performs
additional renderer/sentinel walks. These stacks occur in CPU samples and are
absent from the ordinary entry point. Their load grows with mounted UI complexity.
Absence within particular slow-frame bodies does not eliminate their effect on
overall contention or frame scheduling. Future controlled comparisons should
cache controller references and remove readiness tree walks during measurement,
keeping the FrameTiming callback and checking readiness afterward.

Raster spikes are separate from the worst UI paint frames. Recorded raster
maxima are 58.533 versus 55.317 ms; their paired UI builds are only 0.688–1.408 ms.
Candidate engine Encode/Submit/raster spans contain long wall-time intervals,
sometimes overlapping long UI message/post-frame intervals. Neither this nor
sparse samples establishes GPU/driver CPU as the cause. The baseline Timeline
also has a 1.165-second global gap covering its 58.533 ms raster frame: FrameTiming
is retained, but native/GC begin/end durations crossing the gap are invalid.

Next measurement: replay exactly the same text, formatting and arrival cadence
with identical typing, lighter observers and before/after order reversal. Capture
a short Android system trace with scheduling, CPU frequency/idle, FrameTimeline
and SurfaceFlinger/fence events around the stalls. This distinguishes running CPU,
being runnable but unscheduled, and blocking/waiting. Existing live comparison
does not isolate how much of the higher p99 comes from the code change itself.

### 2026-10-02: emulator verification before the next phone window

User authorized emulator-first preparation while away; no physical phone was
accessed. Prepared matching profile APKs in ignored `build/render-replay-ready/`
(`control.apk`, `fixed.apk`, `ready-manifest.json`, `source-comparison.json`).
Both target only `com.tarkilhk.wing.perfqa`, version 2357, share the same signing
certificate and ARM64/x64 Flutter engine. The source difference removes only the
growing-paragraph retention adapter from the control. Production Wing and stock
Hermes remain untouched; these synthetic runs issue zero backend/model requests.

The profile-only `workspace_streaming_replay.dart` uses the actual workspace and
controller with an injected gateway fixture: six initial mixed-format sections,
six growing sections, 400 deltas on absolute 50 ms deadlines, stock completion
receipt and authoritative history. Native typing supplies exactly 60 characters
on absolute 250 ms deadlines while streaming. Measurement avoids periodic widget
tree walks; readiness walks occur before or afterward. SharedPreferences are
mocked in memory, intentionally excluding native draft-storage cost. This is a
renderer comparison, not a complete live backend or persistence benchmark.

Guards verify final authoritative source, rendered segment inputs/parser
readiness/final laid-out sentinel, exact typed draft, focus and keyboard stability,
viewport/DPR/text scale/display rate, actual chunk/input timing, host/VM clock
calibration, ordered ABBA labels, matching trace/replay bounds and restored VM
profiler state. Rendered readiness is not a pixel-for-pixel assertion over every
character. Interrupted or unequal workloads are rejected.

All four emulator ABBA workloads passed, with identical source/draft hashes and
zero trace data loss. Streaming UI p99: control 22.345 and 24.226 ms; fixed 17.446
and 17.469 ms. Streaming frames above 16.667 ms: control 32/33; fixed 11/10.
Whole measured UI-thread Running time: control 7.656/7.816 s; fixed 6.303/6.746 s.
See `build/render-replay-ready/emulator-abba/controlled-comparison.json` and the
per-run numeric system summaries. These are emulator observations, not predicted
phone performance. The emulator uses software graphics at 60 Hz and native key
events rather than the phone's SwiftKey taps; raster timings are not comparable
with the phone. Two replays per arm do not establish a confidence interval.

Preparation exposed and resolved test-tool defects: an emulator System UI ANR
blocked keyboard opening; Flutter's merged main/UI thread was omitted by the old
UI-thread predicate; native perf samples initially overflowed the kernel buffer;
and Perfetto requires flush_period_ms on TraceConfig, not FtraceConfig. Final
traces use observed PAINT tracks to identify merged UI execution, 100 Hz native
sampling with 256 ring-buffer pages, top-level 1 s flush and no data loss. Host
analysis now parses each trace twice, then uses one private indexed SQLite
connection; all window queries take about 3–5 s total rather than minutes.
Temporary databases are deleted. Raw traces stay private in ignored local build
storage; exported summaries omit process/thread names and user content.

Separate emulator diagnostic runs successfully enabled per-RenderObject PAINT
slices and Dart CPU samples (3,078 samples at 1 ms in the initial diagnostic),
with flags restored afterward. Their timings do not enter the paired comparison.
`render_object_attribution.py` attributes static Render classes without counting
nested paint time twice; malformed/incomplete trees are explicitly excluded.
Native sample counts, scheduler Running/waiting intervals and instrumented wall
spans are separate evidence. Some resolved native symbols are only allocator/ART
frames; that does not prove the expensive Flutter/Dart function is identified.

Future phone run, after user go and current ADB address (budget about 8–12 minutes):

1. Check unlocked, screen on, unplugged; record thermal/battery/display state.
   Visually verify SwiftKey keyboard and native tap coordinates.
2. Install/launch QA with trace-systrace, warm preparation outside timing; replay
   control-1, fixed-1, fixed-2, control-2 using identical input/observers. Check all
   workload/trace guards before interpreting differences.
3. If native samples cannot explain the slow UI path, run one separate 20 s
   diagnostic with per-render-object paint slices and Dart CPU sampling. Relate
   expensive paint intervals to Running versus runnable/blocked states and
   function samples; do not treat wall duration alone as consumed CPU.
4. Restore `build/draft-outbox-phone-20261002/artifacts/retained-paragraph-normal.apk`,
   stop/remove the synthetic QA task and tell the user the phone is free before
   doing further host analysis. Production Wing stays unchanged.
5. Choose the next optimization from that phone evidence. A live Luna/Hermes
   confirmation remains appropriate after choosing a fix.

Follow-up probe validation: per-object PAINT timelines account for 70 of 126
leaf samples inside 20 slow paints through `_reportTaskEvent`, a substantial
observer effect. The lighter Dart-only probe has zero such leaf samples, with
41 samples inside 13 slow paints; observed leaves include native text paint and
picture recording. Therefore the phone attribution sequence starts with
Dart-only sampling and native scheduler/stacks. Per-object tracing is optional,
separate, and used to locate classes rather than claim uninstrumented costs.
The attribution helper also computes exclusive scheduler Running/runnable/etc.
for each Render type's gaps, retains unobserved coverage explicitly, and rejects
invalid state overlap. The CPU sanitizer now preserves safe static Class/Function
owner names to distinguish otherwise generic `paint` methods. Native APK-backed
mappings retain safe `app_apk` address/build-ID/container-offset metadata for later
symbol resolution; libc/ART resolution alone is not Flutter leaf attribution.

Final lighter diagnostic passed all workload guards, with zero trace data loss,
2,416 Dart samples and class-qualified profiler entries successfully exported.
It identifies, for example, ContainerLayer.detach/attach, PaintingContext.paintChild
and Layer composition callbacks separately. These emulator observations verify
attribution capability; they do not establish the phone hotspot. Final checks:
17 focused Flutter tests, 62 Python host tests, clean Flutter analysis and
`git diff --check`. Emulator verification is complete; prepared phone APKs and
restoration artifact remain ready, pending user go/current address.

### 2026-10-02: controlled phone ABBA and Dart attribution completed

User supplied go at `10.30.1.2:33137`. Phone was unlocked/unplugged; SwiftKey Beta
and its letter/space tap geometry were verified on the synthetic QA screen.
The native-keyboard guard now targets that actually installed IME directly.
An initial final-control preparation failed because the keyboard did not open;
preparation succeeded on retry outside measurement. No failed preparation enters
the comparison. No backend/model calls were made by these offline fixtures.

Artifacts: ignored/private `build/render-replay-ready/phone-20261002/`, including
`controlled-comparison.json`, each replay/system summary, and
`diagnostic/fixed-1/{dart-cpu.json,system-summary.json}`. All four ABBA guards pass:
identical source/draft hashes, keyboard/viewport/DPR/font/display values,
400×50 ms deltas, 60×250 ms native inputs, timing/clock boundaries, ordered arm
labels, restored profiler state and zero trace-data-loss counters. Native stacks
were supported on this phone. The panel reports 120 Hz (8.333 ms period).

| Streaming measurement | Control 1 | Fixed 1 | Fixed 2 | Control 2 |
| --- | ---: | ---: | ---: | ---: |
| UI p95, ms | 7.458 | 7.167 | 7.466 | 8.356 |
| UI p99, ms | 10.069 | 10.035 | 10.300 | 10.404 |
| UI max, ms | 14.507 | 16.565 | 15.749 | 15.968 |
| UI frames >8.333 ms | 71/2033 | 69/2097 | 72/2070 | 99/1978 |
| UI frames >16.667 ms | 0 | 0 | 0 | 0 |
| Raster p99, ms | 3.890 | 4.232 | 4.243 | 4.061 |
| Whole measured UI thread Running, s | 9.200 | 8.504 | 8.700 | 9.475 |

The fixed p99 lies inside the control range: this phone comparison does not
demonstrate a p99 improvement, despite the emulator improvement. Lower total
UI-thread Running time in the fixed arms is a favorable observation, not proof
of instruction-count or battery savings; two repetitions and varying DVFS/
temperature do not establish confidence bounds. Completion frames are separate:
control maxima 20.752/17.839 ms, fixed 18.030/13.958 ms. One completion transition
per run is insufficient to prove a tail improvement.

Selected first 20 streaming UI frames >10 ms spend 96.8–99.3% of their wall time
Running on CPU, with no sleeping/blocked intervals. In slow frames, LAYOUT uses
about 60% and PAINT about 20–22%; BUILD often nests inside LAYOUT and is not added
again. No complete QA PAINT slice exceeds 10 ms in any arm; first-control PAINT
max is 5.059 ms. The old 40 ms UI paint stalls were not reproduced by this
controlled workload. This does not prove they are eliminated in every scenario.

A separate Dart-only diagnostic (not substituted for paired timing) resolves
function owners. Of 457 samples in 45 slow streaming frames, 274 lie in actual
LAYOUT spans, 81 in PAINT, and 102 elsewhere; 134/457 stacks are truncated.
Layout has 201 inclusive samples under `_RenderLayoutBuilder.performLayout`
and 193 under rebuilding with constraints. This locates rebuilding during layout;
it does not establish that LayoutBuilder should be removed.

One concrete code path is fully captured in 31 of 274 slow-layout samples:
`_RegExp._ExecuteMatch → firstMatch → splitMarkdownCodeBlocks →
_MarkdownMessageContentState._buildContent`. Current fence splitting repeatedly
searches copied suffix substrings. Next narrow experiment: scan line boundaries
forward and apply the existing opening/closing regexes only at candidate fence
lines, preserving exact fence, preview and unfinished-fence semantics. Verify
identical outputs for every fixture prefix plus backticks/tildes, indentation and
CRLF before benchmarking. This is roughly 11% of sampled slow-layout work; it is
not a demonstrated solution to the entire ~10 ms p99.

Repaint work is also sampled: across all diagnostic PAINT spans, 222 paragraph
paint leaf samples include TextPainter.paint; 198 include RenderParagraph.paint
and 24 RenderEditable.paint. Picture end-recording has 123 leaf samples. These
identify classes and calls, not individual widget instances or exact CPU time.
Platform queries occur in 19 slow-layout samples, but 13 stacks are truncated;
we cannot assign them confidently to the composer rather than selectable text.
No composer-isolation recommendation is justified by this capture alone.

Per-object paint tracing was left disabled. `_reportTaskEvent` is absent from
slow PAINT leaf samples and is 16/457 slow-frame leaves overall, unlike the heavy
per-object emulator probe. Native installation paths embedded in VM function
names are now stripped from exports; static Class/Function owners remain. Raw
traces and numeric exports stay private/local.

Presentation limitation: FrameTimeline has global SurfaceFlinger display rows
but no QA surface rows. First-control global display-end gap p99 is 25.004 ms,
max 41.683 ms, but those events cannot be attributed to Wing. Panel 120 Hz,
Flutter callback counts and build/raster timings do not establish Wing's actual
presentation FPS or app-specific frame gaps. No claim of smooth locked 120 fps.

Android thermal status stays 0 at start/end (no reported throttling). Battery
sensor rises about 34.1→37.2°C and AP sensor 40.3→42.0°C. Battery percentage
66→62 during the active screen/typing/tracing/install window is not an idle
battery comparison or a measurement of release-app battery use.

Ordinary QA `retained-paragraph-normal.apk` was restored successfully, the QA
process was stopped and the phone returned to the user before further host
analysis. Production Wing and Hermes were unchanged. QA task records remain in
Android recents; removal was not verified (do not report them as removed).
Host checks after keyboard/export updates: 64 tests pass and whitespace checks
are clean. Current ready APKs were not rebuilt for these host-only updates.


### 2026-10-02: fence scanning joins the existing background worker

Committed and pushed all previous optimization work as `3657157` before this
implementation. The ordinary chat renderer now sends each complete presentation
snapshot to the existing single `wing-markdown-parser` isolate. That job splits
fences and resolves prose into Dart-only segments; the UI constructs widgets from
one accepted result. Fence grammar is unchanged. Parser/cache state remains per
mounted owner and prose position, preserving the existing per-segment reference
scope and reusing unchanged completed prose.

The existing controller presentation window remains 100 ms. No second batching
timer or worker pool was added. Each mounted message permits one in-flight job
and retains only the newest pending source. Completed progress is displayed
before the next job, avoiding starvation during bursts. Replacement, grammar
changes, disposal and backgrounding invalidate late results. Resuming prepares
the latest source. Completing unchanged source enables closed code previews
without rescanning it. Linked document previews retain their existing synchronous
heading-anchor path, and explicit synchronous benchmark variants remain available.

Worker metrics distinguish fence/parse wall time from request turnaround, which
also includes queuing, transport and the UI accepting results. Character-backlog
metrics count UTF-16 code units, not elapsed delay. Profile-only preparation spans
and aggregate counters record no message contents. The replay exports readiness
and numeric worker counters only after measurement.

Validation: 2,766 Flutter tests passed with 17 existing opt-in/platform skips;
67 host tooling tests passed; Flutter analysis reported no issues. The four
original-scanner prefix digests were also checked against the actual committed
Dart implementation. A whole-message parser regression fails on that baseline
(two prose parsers) and passes on the new path (one message parser). Tests cover
mixed and unfinished fences, references, AST mutation/copy isolation, cache
release, coalescing, failure/disposal/lifecycle, completion, code copy/wrap,
selection and reader-position retention across themes and enlarged text.

Emulator ABBA results are in ignored `build/fence-worker-ready/emulator-abba/`.
All four workloads passed final-source/segment-readiness, identical typing,
keyboard/viewport, cadence, trace-loss and profiler-restoration guards. The
fixture sends 400 deltas over 20 seconds while native typing supplies 60
characters. No physical phone or Hermes backend was accessed. The emulator uses
60 Hz GBoard and software graphics; this does not predict phone performance.

| Streaming UI timing | Control 1 | Fixed 1 | Fixed 2 | Control 2 |
| --- | ---: | ---: | ---: | ---: |
| p95 (ms) | 11.867 | 11.500 | 11.619 | 10.701 |
| p99 (ms) | 18.427 | 17.674 | 19.496 | 17.080 |
| Maximum (ms) | 28.583 | 26.375 | 40.132 | 25.206 |
| Frames over 16.667 ms | 9/837 | 12/830 | 14/799 | 10/846 |

There is **no demonstrated p99 improvement** in this emulator comparison. Both
fixed runs completed all 25 segments with one owner, no pending/stale results,
and zero updates coalesced behind a busy job. Tracked fence+parse wall totals
were 285.078 ms across 195 jobs and 279.459 ms across 194 jobs, including initial
preparation (about 1.46/1.44 ms per job). Maximum request turnaround was
39.152/51.742 ms, including preparation and delivery. These aggregate maxima
lack timestamps and cannot be tied to the 40.132 ms frame.

Fixed-2 also had worse raster p99 (44.863 ms versus 39.272–39.488 ms in the other
three runs). The saved system summaries do not identify the cause: the initial
window cap selected the first 20 slow frames and missed the worst late frames;
these ABBA traces also lack PAINT slices establishing the UI thread role. Do not
attribute that maximum to parsing or software-GPU contention from these files.
The host capture now selects the longest 20 contained build/raster windows,
recording selection policy `1`; its regression covers late maxima, bounds and
stable ties. Existing ABBA archives were not rewritten.

Separate CPU diagnostic runs in `build/fence-worker-ready/diagnostic/` verify the
actual move: baseline main-isolate samples include 22 scanner stacks out of
2,115 samples; fixed main has zero observed scanner stacks out of 2,210, while
the worker has 24 out of 171. Main traces include 154/191 truncated stacks;
worker stacks are untruncated. Counts are sampled attribution, not milliseconds
or exact CPU percentages. Timings from these diagnostic runs are excluded from
ABBA; only the fixed diagnostic enabled Android systrace, so their system spans
are not a matched performance pair.

Both QA comparison APKs use the same ARM64/x64 Flutter engines and application
version. Native JNI library artifacts also differ between source-directory
builds; this is not a byte-identical-native-library comparison. Normal-size
emulator screenshots retain the same table/code/composer geometry. Widget tests
cover theme and enlarged-text behavior; this is not a full pixel comparison.

Next phone window: install the prepared ordinary QA build, validate live Luna
streaming with typing/scrolling, and run a matched baseline/new comparison with
systrace enabled consistently and the corrected longest-window coverage. The
ordinary production app and the physical phone were untouched during this
emulator preparation. The subsequent authorized phone window is recorded below.

## October 2 phone validation: background fence preparation

Compared committed baseline `3657157` against background-fence-worker commit
`0c34639`, both already pushed to `main`. The S23 Ultra remained unplugged at
120 Hz with SwiftKey Beta. Both APKs were launched with identical Dart-profiling
and Android-systrace flags; Dart CPU sampling was disabled for all comparison
runs and identical native 100 Hz sampling was enabled. The order was baseline,
updated, updated, baseline (ABBA), restarting the app for each run. Only the
`com.tarkilhk.wing.perfqa` package was installed; production was not installed
or modified. Reinstalling with `-r` preserved QA's existing Hermes connections.
Controlled replays use memory-backed preferences (`nativeDraftStorage=false`),
excluding native draft-persistence cost; the live app uses ordinary persistence.

One preliminary control was excluded: ADB delayed the native input schedule by
1.056 seconds, failing its 500 ms timing guard despite the correct final draft.
The repeated control and all three subsequent runs passed the existing workload,
keyboard, geometry, cadence, source/draft hash, profiler-restoration and trace
guards. Each sent 400 synthetic deltas over 20 seconds while 60 real SwiftKey
characters were entered. All system traces contain PAINT events identifying the
main thread as the UI thread, have zero reported trace loss, and use longest
contained-window selection policy `1`. The comparison reports no issues.

| Streaming timing | Baseline 1 | Updated 1 | Updated 2 | Baseline 2 |
| --- | ---: | ---: | ---: | ---: |
| UI p95 (ms) | 7.426 | 7.377 | 7.099 | 7.505 |
| UI p99 (ms) | 10.299 | 9.322 | 9.175 | 10.509 |
| UI maximum (ms) | 15.224 | 18.406 | 17.768 | 14.393 |
| UI frames over 8.333 ms | 74/1990 | 57/1967 | 40/1969 | 65/1925 |
| UI frames over 16.667 ms | 0 | 1 | 1 | 0 |
| Raster p99 (ms) | 4.508 | 4.419 | 4.839 | 4.830 |
| Completion UI maximum (ms) | 13.400 | 12.732 | 11.318 | 14.562 |

Both updated streaming p99 measurements beat both controls; the mean of the two
p99 values per arm is about 11.1% lower. This is evidence for this controlled
workload, not a general performance guarantee. Rare UI maxima worsened, and
raster p99 did not consistently improve. Completion tails contain only 13–20
frames, so their maxima are more useful than calling their p99 representative.
These are Flutter UI/raster wall durations, not measured displayed-frame gaps:
the app FrameTimeline query returned zero rows, so this capture cannot establish
displayed FPS or claim the previously observed presentation gaps are eliminated.

Android reported LIGHT thermal status (`1`) at every recorded checkpoint;
battery temperature rose from 38.0–38.4°C in the first two runs to 38.8–38.9°C
in the last control.
ABBA order counterbalances some time drift but does not remove thermal effects.
Whole UI-thread running totals were 8.958, 9.157, 9.289 and 9.366 seconds. There
is no demonstrated reduction in total UI CPU or battery consumption.

The updated runs completed 200 worker jobs each, with one whole-message parser,
all 25 expected segments (13 prose/12 code), and no pending/stale parser results
at completion. Fence/parse wall totals were 103.460/176.836 ms and
120.420/190.146 ms; maximum request turnaround was 28.641/30.194 ms. These include
initial preparation and turnaround includes queue/delivery/acceptance; they are
not timestamps attributing an individual slow frame. No update was coalesced
behind a busy job in this fixture.

Scheduler evidence explains part of the remaining maxima. Updated 1's 18.406 ms
UI frame spent 14.701 ms running, 0.099 ms runnable and 3.606 ms blocked.
Updated 2's 17.768 ms UI maximum ran entirely on CPU. The updated raster maxima
had different causes: 11.046 ms included only 2.871 ms running and 8.175 ms
runnable; 11.798 ms included 2.607 ms running, 0.217 ms runnable and 8.974 ms
sleeping. No complete PAINT slice exceeded 10 ms. Native samples in the largest
UI windows are sparse and contain unresolved APK addresses, so these records
do not identify an exact expensive painter or widget.

### Live Hermes integration and CPU attribution

Installed the current profile observer build and created one explicitly owned
QA conversation using `gpt-5.6-luna`/`openai-codex`, preserving profile defaults.
One mixed-format prompt produced a complete 11,604-character response with
headings, a table and Dart code fences. No tool/subagent activity or controller,
chat or dispatch error was recorded. The full final source was renderer-ready
with zero pending parses, and the ten-character test draft survived completion.
The final sentinel was visually confirmed after tapping New activity; the
observer's earlier sentinel check was false while reading a different part of
the virtualized answer.

The live script issued 40 key-coordinate taps, but its first deliberate reading
scroll dismissed SwiftKey after ten actual typed characters. The remaining taps
are not evidence of typing. Sustained 60-character typing is verified by the
four controlled replays; the live run verifies shorter typing plus scrolling
during a real response. Do not present it as 40 typed characters or a completed
full-length live typing stress test.

Main-isolate CPU sampling recorded 18,846 samples, including 1,127 truncated
stacks and 24 empty stacks, with zero observed `splitMarkdownSegments` stacks.
The worker recorded 186 untruncated/nonempty samples, including eight scanner
stacks. This corroborates the move to the background worker on the real phone;
zero observed samples alone would not prove absence of all UI scanning.
Observer `_Measurement`/`_walk` stacks account for 2,848 main samples and must
not be counted as application rendering. Many main `write` samples include
timeline-reporting calls, so the tracing overhead also prevents interpreting
all writes as app paint work. Counts are sampled attribution, not exact CPU
milliseconds or disjoint categories.

The five longest UI frames starting inside the live observed streaming window
contain 86 main-isolate samples, 40 with truncated stacks. None identifies the
observer, fence scanner or `MarkdownCodeBlock`. Repeated identifiable ancestors
include `RenderEditable.performLayout` (10 samples), `TextPainter.layout` (9),
`LayoutBuilder.rebuildWithConstraints` (9), `PipelineOwner.flushLayout` (13) and
`flushPaint` (9). These overlap; they support investigating editable/text layout
and layout-time rebuilding, not assigning exact durations or identifying the
composer as the responsible widget. In particular, the misplaced post-scroll
taps could exercise transcript selection instead of typing. One 21.737 ms frame
ends only 6.485 ms before observed completion, so polling cannot exclude
completion work from that frame. The four other peaks occur before the final
full response. This is a diagnostic lead, not proof of an expensive painter.

Live streaming UI p99 was 10.214 ms (maximum 22.522 ms), and raster p99 was
4.732 ms. That run had a different response, native draft persistence, Dart CPU
sampling and periodic observer tree walks; it is not a matched speed comparison
with ABBA. Readiness observations use 20 ms source and 100 ms render polling;
the reported first-text-to-ready 113.134 ms and completion-to-ready 22.574 ms
are observation differences, not exact processing durations.

Private ignored evidence is under
`build/fence-worker-ready/phone-20261002/`: `replays/controlled-comparison.json`,
per-run scheduler summaries and raw traces, `excluded/control-1-input-stall/`,
and `live/` numeric reports and sanitized main/worker samples. Chat text,
credentials, VM-service URLs and device screenshot contents are not committed.
The phone was released after restoring the ordinary QA APK; its installed
SHA-256 was verified as
`15e09d7b53440359ac0f2102f21175bd48133799cbadd84a39b7f61b85888c7f`.
No further phone input is needed to analyze these saved files.
Full sustained live typing still needs a repeat if validating that specific
stress case: keep the keyboard visible for the complete verified input sequence,
then exercise scrolling, or explicitly reopen and verify it after every scroll.
