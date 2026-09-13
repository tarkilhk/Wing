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

## Final results

The finite batch is complete. R01–R05 and R07 passed. R08 proved usable file
contents and durable reopen, but automatic reference expansion still encounters
the backend workspace restriction described below. R06 could not reach a vault
form because the configured local browser runtime failed. Neither limitation is
reported as a passing test or an Android fix.

| Case | Required real acceptance | Status |
| --- | --- | --- |
| R01 | Open a server-downloaded PDF, change page, pinch to zoom, return. | Passed. Native page 1/page 2 rendering, centered pinch-out/in, and Back were verified. Enlarged PDF text is captured in `qa-media-pdf-centered-zoom.png`. |
| R02 | Open a server-downloaded SVG/image; pinch zoom and return. | Passed. Real SVG WebView and PNG viewer accepted pinch-out/in; before/after captures show the enlarged content. Both returned to Outputs. |
| R03 | Download/play WAV, MP3, H.264 MP4 and WebM; verify timeline advances, pause, seek, background/resume, and Back. | Passed through normal signed app and real Hermes downloads. All four native Play/Pause/Seek tests passed; MP4/WebM decoded images were visually verified. WAV completed at 18 s, seeked to 7 s, and restored that paused position after stop/resume. Back returned to file actions. |
| R04 | Open media through a Markdown file downloaded from Hermes. Invalid media offers a useful return/save/open path. | Passed. `links.md` opened its WAV through the real file client; native Play/Pause/Seek passed. Invalid MP4 displayed the format error with instructions to return and open/save/share; Back returned successfully. |
| R05 | Receive a real manual approval, act on its card, and verify the saved tool result. | Passed. Both Deny and Allow once were exercised on real cards, cleared after response and completed with saved results. The command targeted an owned disposable repository containing one empty commit. |
| R06 | Receive and submit/cancel real vault OTP/save-login forms with dummy data; verify no draft/history leakage. | Unavailable in the configured local environment. Stock browser execution timed out, then reported an unavailable browser before emitting a vault request. The owned turn was stopped. No form response was tested; external-manager unlock also lacks a configured manager. |
| R07 | Original remote server: authenticated diagnostics, existing QA chat reopen/context, fresh nonce reply and durable reopen. | Passed on signed 2.31.19 in the emulator. Password login, profiles/chats, authenticated dashboard diagnostics, configured provider and credential readiness succeeded. A fresh unique reply was independently verified in saved history. That chat reopened with both exchanges and about 16,119 / 272,000 context tokens. Older owned QA chat `20260913_125250_47e82b` reopened with saved history and about 54,027 / 272,000 tokens. Code 5000 did not recur; the original failure's cause remains unproven. |
| R08 | Original remote server: attach a synthetic file whose content marker is absent from the prompt/filename; verify content-based reply and reopen. | Content delivery and reopen passed, with a backend limitation. Android's Files picker uploaded the 53-byte fixture, Hermes read its independent marker using `read_file`, and the correct reply persisted. Saved history still contains `path is outside the allowed workspace` from automatic `@file` expansion. The successful tool read does not establish successful automatic expansion. Current Desktop/Android source parity was reconfirmed; no client workaround or backend change was made. |

### Remote evidence and attachment boundary

Evidence is under ignored `build/qa-remote-acceptance/`: `nonce-reply.xml`,
`nonce-saved.json`, `file-reply.xml`, `file-saved.json`, `reopened.xml`,
`older-chat.xml`, `admin.xml` and `diagnostics.xml`. The fresh session is
`20260914_030533_d48503`. The file marker was absent from both its filename and
the prompt. Its saved `read_file` result contains the actual 53-byte content,
followed by the exact marker reply. The Activity section remained collapsed.
The remote administration screen reported backend version/update status as
unavailable; dashboard authentication and provider readiness checks passed.
No backend update was attempted.

The source recheck used the available official Desktop checkout:
`use-prompt-actions/index.ts:191–205` calls `file.attach` and accepts `ref_text`;
`submit.ts:750–755` submits the synchronized references. Android does the same
in `profile_workspace_controller.dart:3804–3826`. Stock
`tui_gateway/prompt_attachments.py:82–174` stages files under profile-home
`attachments`, while `agent/context_references.py:168–195,269–274,342–345`
restricts expansion to the workspace. A staged absolute path can therefore be
outside that boundary. There is no verified upload-destination parameter for
Android to correct this. Rewriting the reference or pasting file bytes would
depart from Desktop's contract. See
[attachment parity](DESKTOP_ATTACHMENT_REGENERATION_PARITY.md).

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
