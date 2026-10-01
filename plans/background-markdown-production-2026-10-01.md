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

Deployment and live results will be recorded after completion; no live result is
claimed by this initial promotion record.
