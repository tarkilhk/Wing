# Remaining real-backend acceptance

This is the finite continuation of the 2026-09-13 QA sweep. Tests use stock
Hermes and disposable data. No backend code, database repair, global settings
or credential changes are part of this work. Feature releases proceed in
separate tasks; QA changes stay outside their release commits.

## Completed baseline

2.31.11 passed 1,343 tests with four opt-in skips and clean analysis. Seven
real-backend acceptance scenarios passed, plus the separate native Activity
collapse/alignment and real sudo cancellation check. The signed build was
installed and cold-launched on the phone. These are not claims of exhaustive
phone coverage.

The later 2.31.19 source `b1eb106` also passed
[GitHub PR Quality Checks](https://github.com/tarkilhk/hermes-android/actions/runs/34771639067).
That release's focused display-type tests and CI results cover its changes;
this acceptance batch does not repeat the full suite solely for QA documentation.

QA-034 cancellation and stock expiry resume the expanded skill prompt exactly
once and clear the submitted draft after the backend accepts it. The previous
ledger wording about preserving an unsent draft was incorrect.

The real local Hermes file-download endpoint returned all nine synthetic files
with exact SHA-256 matches: PDF, SVG, PNG, WAV, MP3, MP4, WebM, invalid MP4 and
Markdown containing file links. Evidence: `build/qa-real-media-downloads.json`.
This verifies transport only; it does not substitute for native playback/zoom.

## Cases to finish

| Case | Required real acceptance | Status |
| --- | --- | --- |
| R01 | Open a server-downloaded PDF, change page, pinch to zoom, return. | Passed. Native page 1/page 2 rendering, centered pinch-out/in, and Back were verified. Enlarged PDF text is captured in `qa-media-pdf-centered-zoom.png`. |
| R02 | Open a server-downloaded SVG/image; pinch zoom and return. | Passed. Real SVG WebView and PNG viewer accepted pinch-out/in; before/after captures show the enlarged content. Both returned to Outputs. |
| R03 | Download/play WAV, MP3, H.264 MP4 and WebM; verify timeline advances, pause, seek, background/resume, and Back. | Passed through normal signed app and real Hermes downloads. All four native Play/Pause/Seek tests passed; MP4/WebM decoded images were visually verified. WAV completed at 18 s, seeked to 7 s, and restored that paused position after stop/resume. Back returned to file actions. |
| R04 | Open media through a Markdown file downloaded from Hermes. Invalid media offers a useful return/save/open path. | Passed. `links.md` opened its WAV through the real file client; native Play/Pause/Seek passed. Invalid MP4 displayed the format error with instructions to return and open/save/share; Back returned successfully. |
| R05 | Receive a real manual approval, act on its card, and verify the saved tool result. | Passed. Both Deny and Allow once were exercised on real cards, cleared after response and completed with saved results. The command targeted an owned disposable repository containing one empty commit. |
| R06 | Receive and submit/cancel real vault OTP/save-login forms with dummy data; verify no draft/history leakage. | Unavailable in the configured local environment. Stock browser execution timed out, then reported an unavailable browser before emitting a vault request. The owned turn was stopped. No form response was tested; external-manager unlock also lacks a configured manager. |
| R07 | Original remote server: authenticated diagnostics, existing QA chat reopen/context, fresh nonce reply and durable reopen. | Emulator prepared with signed 2.31.19. The remote server requires both username and password. Host, port and password have been entered through the normal connection form; username remains required before authentication can be tested. This is not a remote acceptance result. |
| R08 | Original remote server: attach a synthetic file whose content marker is absent from the prompt/filename; verify content-based reply and reopen. | Waiting for the remote username and successful emulator login. A synthetic file and independent marker are prepared and the file is on the emulator; no remote attachment was submitted during this attempt. The phone has been released and its original screen timeout restored. |

## Scope limits

The approval probe uses the terminal tool's `workdir` field and the literal
command `git reset --hard`. The initial model-generated `git -C ... reset
--hard` ran without a card because it did not match the stock detector's
`git reset` pattern in `tools/approval_detection.py`. It is excluded from the
card acceptance result. Corrected card/result evidence is in
`build/qa-manual-corrected-card.png`, `qa-manual-denied-result.xml`,
`qa-manual-allow-card.png` and `qa-manual-allowed-result.xml`.
Independent server-history readback confirms session
`20260914_012337_3498d2` saved a blocked terminal result after Deny, and
`20260914_012558_46b11c` saved exit code 0 with explicit user-approval metadata
after Allow once. Both then saved their final assistant response. Readback
evidence is `build/qa-manual-saved-results.json`.

The R03 run used signed 2.31.12 on the emulator, which supports ARM64. The
relevant Outputs, PDF, image, WebView, file client and native media source files
are unchanged through 2.31.18, verified by a scoped Git diff. Evidence includes
`build/qa-media-native-controls.log`, per-format `qa-media-*-controls.log`,
`qa-media-wav-restored.xml`, `qa-media-mp4-playing-frame.png` and
`qa-media-webm-tested.png`. Native controls changed Play to Pause and back, and
each seek ended at 11 s. The first gesture-helper invocation failed before
testing because Android 36 lacks legacy runner annotations; the repaired
helper's actual passing invocations are distinct from that failed run.

One long `adb input text` injection left a 75-character prefix in the composer;
normal Android share intake delivered the same complete 1,164-character text
to the draft and the real saved conversation. A bounded 150-character keyboard
comparison was inconclusive: Android Settings became unresponsive, and the
Hermes control tap landed outside the composer. This does not establish normal
typing data loss. No speculative composer change was made. Evidence is
`build/qa-media-draft-settled.xml`, `qa-media-ready.xml` and
`qa-input-settings-filled.png`.

- Local profiles advertise only the configured `openai-codex` route. Additional
  providers/proxy arrangements are not passing cases without a configured
  endpoint. Test at most two genuinely configured remote routes.
- External Bitwarden/1Password unlock requires an installed, configured manager.
  Neither is available in the current local test environment. The stock
  local-vault recipe also requires a working browser. Session
  `20260914_011625_691531` failed that prerequisite with a 120 s browser timeout
  and a subsequent missing-browser error. Evidence is in
  `build/qa-vault-request.xml` and `build/qa-vault-stopped.xml`. No backend
  browser repair or configuration change is authorized by this QA work.
- QA-031 non-default loop scope and unseen child-only activity recovery depend
  on existing server contracts. Do not modify Hermes to make a test pass.
- FCM, broad administration and other explicitly deferred roadmap items remain
  deferred. They are not added to this acceptance batch.
- Emulator audio playback/timeline and native decoding do not establish that a
  particular physical speaker was heard. Record that distinction precisely.
