# Twenty-minute phone validation window

Completed on 19 September; see [results](2026-09-19-phone-results.md). The owner
subsequently allowed extra time. The core sequence took 376.6 seconds, followed
by three native-120 Hz runs and final restoration to ordinary Wing Dev 22674.
This document preserves the prepared procedure and kit versions. Reusing it now
requires a newly numbered kit because downgrades are deliberately rejected.

The owner will provide the phone's current wireless ADB `address:port` on arrival.
Do not search for the phone while it is away. Start the clock at that handoff.
Keep it unlocked and available for the twenty-minute window.

## Ready before arrival

- Source: `3cc7628` application code, including freshly fetched `origin/main`
  (`def56b2`). Only benchmark tooling changes in this preparation.
- Baseline: unoptimized `def56b2` application, AOT profile mode, ordinary Dev
  identity/signing, version 22670. Same measurement entry point as the candidate.
- Candidate: fixed application, AOT profile mode, version 22671.
- Normal build: fixed application with the ordinary entry point, version 22672.
- All APKs include arm64 for the Samsung phone and x86_64 for emulator rehearsal.
  Package remains `com.tarkilhk.wing.dev`. Install with `-r`, preserving settings,
  connections and drafts. Never uninstall or attempt a version downgrade.
- Prepared artifacts and SHA-256 manifest: `build/phone-performance-kit/`.
- Production Wing (`com.tarkilhk.wing`) is outside this test.
- Recheck remote main before the window. If it advances, reconcile the kit source
  before starting; do not present old artifacts as the new main.

## Time allocation

| Minutes | Work |
| --- | --- |
| 0–2 | Connect/authorize ADB, verify installed version and real-backend screen; record display mode, battery/thermal context and resolution; save refresh-rate settings and request 60 Hz. |
| 2–5 | Install/warm baseline; three 30-second scroll runs including refresh. Capture visible loading-error state separately from timing. |
| 5–6 | Stop baseline, install candidate and allow the baseline's password-login attempts to age out of Hermes' 60-second rate-limit window. |
| 6–9 | Confirm real profiles loaded; same three 30-second scroll runs, with no builds, CPU profiler or screen recording running. |
| 9–12 | Five consecutive awaited real refreshes; check connected status and visible profile errors after each. Brief background/foreground recovery check. |
| 12–16 | Inspect timing and reliability results; if needed, use remaining time for one focused capture/rerun of the failing scenario. |
| 16–20 | Hard cutoff for testing. Install the normal candidate, restore original display settings, verify the screen and report results. |

The existing repeated/overlapping-refresh regression tests cover duplicate reads;
phone gestures and service-triggered refreshes exercise the installed production
callback. No chat is created or sent. No network toggle is used, since disabling
Wi-Fi would sever wireless ADB. Do not run performance tests while the phone is
thermally throttled without recording that limitation.

## Start command

From the repo after sourcing the workspace toolchain:

```sh
python3 tools/qa/phone_chat_window.py \
  --serial ADDRESS:PORT \
  --kit build/phone-performance-kit \
  --output /tmp/wing-phone-acceptance
```

The runner verifies APK hashes and installed version, records each phase, enforces
a 16-minute work alarm and always attempts restoration. The final four minutes
are reserved for cleanup and human-readable reporting. ADB authorization issues
must be raised immediately; do not silently spend the window retrying pairing.
Inspect `display-during.txt` to confirm the phone actually selected 60 Hz; requested
settings alone do not prove its display mode. Compare the two builds at identical
resolution, density, theme, filter/group settings and actual refresh rate.

The frame harness uses a benchmark-only local Dart service extension to return
the list to the top without generating accidental extra refreshes. Its snapshot
exports only readiness, connection status, profile count and visible error counts.
No chat text, profile names, credentials or VM access URLs are written to reports.
`check_chat_refreshes.py` awaits the actual RefreshIndicator future and observes
the next rendered frame before checking errors. It does not infer success from a
sleep. The normal distributed APK includes none of these benchmark extensions.

## Acceptance and reporting

For each of three candidate runs, both UI and raster p95 must be <=16 ms and p99
<=32 ms. Report frame counts, tails and above-budget counts, not just averages.
Five refreshes must complete with no loading errors; background/resume must return
to Connected. Preserve the full index, group totals and approved three-row preview.
Record baseline failures honestly; their old login behavior is expected to be able
to hit HTTP 429. A slower/failing run is evidence, not a reason to discard a sample.

Phone results are separate from emulator results. A phone pass cannot be relabelled
as proof that the software-rendered emulator met the original raster target. Keep
that distinction explicit when updating the goal's acceptance evidence.

If a test fails, save the evidence and finish within the window. Do not start a
speculative rebuild loop or claim the goal is complete. Preserve the final ordinary
APK and the results so analysis can continue after the phone disconnects.
