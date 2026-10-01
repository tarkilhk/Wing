# Background Markdown production promotion and live stress test

The owner approved production promotion of the guard, inline cache and reusable
parser isolate on 1 October 2026. The previous QA measurements remain in
`background-markdown-qa-2026-10-01.md`; they are not live-stream measurements.

## Production changes

Background parsing is the ordinary default, including the regex guard and inline
cache. The explicitly selected benchmark variants remain measurement references.
Production keeps the existing package and signing certificate; the base build is
2357 (ARM64 split version code 23572).

Enabling the worker across the full suite revealed a real saved-reading-position
regression: reopening could add 120 px from temporarily empty Markdown bodies.
The transcript now retains the original saved offset until initial content is
ready, without persisting temporary clamps. Single long answers are covered.
User gestures, Latest, expansion and explicit notification navigation release
restoration. Ordinary subsequent streaming anchoring remains enabled. Terminal
parser errors release pending state and publish a layout-change notification.

Tests that previously assumed synchronous text preparation now wait for the
worker without weakening their content, layout or interaction assertions.

Validation before push/deployment:

- Full suite with the production background default: **2,687 passed**, 17 existing
  opt-in skips, 3 minutes 48 seconds.
- Two focused notification navigation cases passed at stored offsets 0 and
  1,000 px; the additional nonzero-offset case was added after its file was
  compiled in the full run.
- Static analysis with fatal infos: no issues.
- Release-tool tests: 28 passed; source version progression check passed.
- Targeted worker/error, single-answer restoration, reopen and later streaming
  growth checks passed. The old 384 px and reader-anchor assertions were retained.

## Live test protocol

Install the signed production APK in place after pushing main. Use the separate
Wing Perf QA identity for Flutter frame/readiness measurements from the same
production rendering code, preserving existing saved Hermes connections.

`tools/performance/live_stream.dart` is a profile-only full-app entry point.
It creates explicitly named owned QA chats, selects an advertised Luna route with
low reasoning per chat, and accepts only fixed prose/mixed test prompts.
All model calls use Luna. Existing chats, profile defaults and backend code remain
untouched. Upstream Hermes HEAD was inspected as
`357f51c49106f47136caf9b01015467b7b633fe8`; test actions use the existing stock
client session/model/prompt APIs. No backend deployment is part of this work.

Exercise long prose and mixed lists/tables/fenced code while tapping the actual
Android keyboard; check draft preservation, final response sentinel and parser
readiness. Exercise reading during growth, completion, owned-chat switching,
cancellation/reopening and a repeated run with saved history. Also exercise the
installed production release with native input and native presentation capture.

Export numeric frame, source-length, pending-state, error and draft-equality
metrics, not credentials or transcript text. Source observations poll at 20 ms
and prepared-content observations at 100 ms; observed delays are coarse bounds,
not exact token-arrival or key-to-glyph latency. Native presentation gaps require
continuous ring coverage and active-scenario bounds. Live model pacing varies;
these runs cannot establish a matched baseline speedup.

Restore the original QA profiler flag and phone settings, stop QA, remove only
its recent task and return production Wing before releasing phone control.

## Deployment and live results

Production commit `fbfecf1` was pushed to main and installed in place on the
owner's SM-S918B, Android 16. The installed APK was pulled back and its SHA-256
matched the signed artifact exactly:
`a146aa94ac7254397c0fd4275ff60d28b3b706a032659563fa737871f718dfec`.
The ARM64 version code is 23572. Existing production and QA app data were kept.
The backend was not modified or deployed.

All six live model turns used `gpt-5.6-luna` through `openai-codex`. The user
selected Luna manually after the initial strict QA preparation check rejected
an agentless resume without a provider field. Current upstream permits that
omission before agent construction; it is not evidence of a wrong model call.
The observer adopted only explicitly named synthetic QA chats and verified Luna
before sending. Preparation also left unused synthetic seeded chats; these did
not invoke a model. No existing personal chat was used for a test prompt.

Functional checks:

- Long live prose completed with the requested final sentence. A 133-key
  SwiftKey run overlapped streaming; the settled 130-character draft survived
  completion and the subsequent QA APK replacement/reopen.
- Live mixed Markdown exercised headings, nested lists, a table and Dart fences.
  The full 10,982-character answer completed with the exact final sentence;
  the 125-key/125-character draft remained equal through completion. The final
  mounted Markdown states were ready, with no pending parsing, chat/controller
  errors, tool activity or subagents.
- Native scrolling while reading older content exposed New activity. Production
  used that control to reach the complete newest answer. Code and table rendering
  were inspected on the phone; wide content retained horizontal overflow.
- The ordinary production release completed a further mixed-content response
  with saved history already present. Its 164-key draft survived streaming,
  completion, navigation to another owned chat and reopening the original chat.
- A further production response was visibly streaming after a 118-key run,
  with its draft retained. Its later native Stop action was too late to prove
  interruption, so it is not counted as a cancellation pass.
- A separate guarded QA run cancelled while 1,479 source characters were
  actively streaming. Status changed from running to cancelled, busy cleared,
  and the marked 114-character composer value remained exactly equal. No errors,
  tool calls or subagents appeared. A later fresh observer adoption after native
  navigation was rejected; cancellation-plus-reopen was not independently
  verified and is not claimed here.

### Frame measurements

The QA mixed run captured a conservative **26.10-second intersection of observed
source growth and native typing**. Its 2,807 Flutter frames had:

| Duration | p95 | p99 | Maximum |
| --- | ---: | ---: | ---: |
| Build | 6.46 ms | 10.45 ms | 15.00 ms |
| Raster | 3.12 ms | 3.82 ms | 8.91 ms |
| Owned-layer presentation gap | 16.67 ms | 25.00 ms | 41.68 ms |

77 builds exceeded 8.33 ms; none exceeded 16.67 ms. Six of 2,804 presentation
gaps exceeded 32 ms. Every adjacent native ring overlapped, with minimum overlap
54 and no empty rings. This QA observer polls and walks widgets on the UI isolate,
so these are instrumented results, not overhead-free production timings.

A first production capture found a 66.68 ms maximum presentation gap, but QA was
still alive and used 4.51 seconds of CPU during that trace. A second production
capture therefore ran with QA force-stopped. Its **27.00-second covered typing
window** contained 2,889 presentation gaps: p95 16.67 ms, p99 33.32 ms, maximum
**66.68 ms**, with 29 above 32 ms (1.00%). All 73 native rings overlapped, minimum
44, with no empty rings; QA had zero observed scheduled CPU. The configured
display period was 8.33 ms. The phone can vary its refresh rate; no refresh-rate
setting was changed.

These production windows include live waiting and content updates, and lack
independent token-arrival observations. Presentation intervals are not themselves
Android jank classifications or measured key-to-glyph delays. However, the worst
production-only interval overlapped **52.84 ms of main/platform-thread CPU** and
4.78 ms of raster CPU, making a main-thread burst a concrete investigation lead.
The longest uninterrupted main-thread running slice was 37.51 ms, with 15 slices
at least 20 ms. Removing QA did not remove the long gaps.

### CPU findings and remaining work

Scheduler CPU during the production-only typing window, expressed as a fraction
of one CPU core (not of all cores): main/platform 37.86%, raster 20.14%, generic
Dart workers 8.50%, whole Wing 80.12%. Generic worker threads cannot be attributed
specifically to the Markdown isolate. This is active streaming/input work, not
an idle or battery measurement.

The earlier production trace also contained 199 SharedPreferences.setString
platform-message spans. Their combined wall duration was 4.82 seconds, which
can include asynchronous waits and does not establish their CPU cost. Draft
persistence is a candidate to inspect alongside stream handling, layout and
garbage collection; no function-level cause is proven. The next useful step is
Dart stack sampling correlated with these main-thread bursts, followed by a
focused fix and identical replay. There is no evidence here to justify another
parser architecture change by itself.

Perfetto provided scheduler and clock snapshots, but no Dart stacks, hardware
cycle counters or usable FrameTimeline rows for Wing's Flutter BLAST surface.
Sparse activity transaction frames are not used to classify Flutter jank.
Clock snapshots established BOOTTIME minus MONOTONIC at 33,568.645142 seconds,
allowing coarse native typing bounds to be clipped correctly. Data-loss counters
were zero in the analyzed traces.

The observer's first-ready figure (797 ms) is **not** first-visible-text latency:
its exact-current-source matching misses previously displayed prepared snapshots
as deltas arrive. A zero completion-readiness observation means the same coarse
sample, not instantaneous painting. The old `finalSentinelVisible` metric only
measured mounted RichText, not viewport visibility; the final tool calls it
`finalSentinelMounted`. Retained controllers after native navigation must be
discarded/re-adopted. The final harness rejects stale-controller mutations and
selection and passed scoped fatal-info analysis. These final harness changes
were not rebuilt onto the phone; the exact tested observer source and APK are
archived locally beside the numeric captures.

Numeric captures, APK hashes, exact tested QA source and CPU analysis are under
ignored `build/live-markdown-production-20261001/`. Screenshots were used locally
for inspection and are not committed. These variable live workloads establish
behavior and expose remaining pauses; they do not establish a matched before/after
speedup or a new battery verdict.

### Phone release

The original QA profiler setting was restored before shutdown. QA was force-stopped
and its active recent task removed; production Wing was returned to the foreground.
The original 30,000 ms screen timeout was restored and read back. No display-rate
override, data clearing, app uninstall or backend upgrade was performed. Phone
control ended before offline analysis and report finalization.
