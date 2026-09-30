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
owned-layer presentation analysis and restoration. Broader coverage still absent:
controlled battery/A-B repeats,
a 20-minute native navigation soak and measured input-to-presentation latency.
These require a later user-arranged window; no overall readiness conclusion or
new phone-control interval is implied.

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
