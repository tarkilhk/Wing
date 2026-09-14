# Desktop process batch audit

The installed Desktop uses text pattern matching for individual process notices.
Its batch delivery path has no corresponding display type or renderer branch.
Android copied the individual-notice branch, including that gap. Desktop parity
alone did not establish that internal messages were fully cleaned up.

## Source and verification

Read-only source audit of the installed
`C:/Users/rober/AppData/Local/hermes/hermes-agent` checkout at
`e16f686706b1e0d5334fd1ae82190058d2a19694`. The Desktop hydration and user renderer
files have no local modifications. No backend or Desktop files were changed.

Run from the Android repository:

```powershell
node tools/qa/audit_desktop_process_projection.cjs C:/Users/rober/AppData/Local/hermes/hermes-agent
```

The audit bundles and executes Desktop's actual `toChatMessages` implementation
and dependencies. It reads the actual `PROCESS_NOTIFICATION_RE` initializer
using the TypeScript syntax tree and applies the renderer's branch condition.
It uses synthetic messages, does not launch the React UI, and does not read
credentials or submit model requests.

| Input | Desktop hydration and renderer decision |
| --- | --- |
| Untyped individual process notice | Process notice with collapsed output |
| Untyped 16-process batch | Human bubble, raw batch text retained |
| Same batch with `display_kind: hidden` | Hidden |
| Same batch with `display_kind: internal_notification` | Human bubble, raw batch text retained |
| `display_kind: async_delegation_complete`, count 16 | System notice |

All five assertions passed on 2026-09-14. The affected conversation was not found
in the local default/profile databases, so this is not a capture of the phone's
actual history response or proof of its connected server's exact revision.

## Exact path

1. `tools/process_registry_notifications.py:14`, `ProcessNotificationBatch.render`,
   concatenates the count-prefixed instruction header and individual notices.
   It produces agent-facing text.
2. `tui_gateway/session_notifications.py:451`, `_notif_dispatch_completions`,
   submits that text without `display_kind` or `display_metadata`. By comparison,
   `_notif_dispatch_event` at line 389 supplies both fields for async delegation.
3. `tui_gateway/prompt_turn.py:547` passes display fields into persistence only
   when the caller supplied them. `_absorb_turn_result` at line 567 also stamps
   durable/live history only when a display kind was supplied.
4. `apps/desktop/src/lib/chat-messages/hydration.ts:288` prefers `display_content`
   over raw content. It hides `hidden` rows and converts four known display kinds
   into timeline events. An untyped process batch remains a user message.
5. `apps/desktop/src/components/assistant-ui/thread/user-message.tsx:80` defines
   `PROCESS_NOTIFICATION_RE = /^\[IMPORTANT: Background process [\s\S]*\]$/`.
   Line 374 applies it to trimmed text. The count-prefixed batch cannot match.
   A matching individual notice strips its wrapper and divides headline/output
   at the first newline, at lines 234–238.
6. Android's `lib/core/models/user_message_delivery.dart` copies that rule and
   headline/output split. It therefore has the same batch gap for the same input.

## Fix after the audit

The owner authorized a narrow client workaround after reviewing the Desktop
finding. The initial full-instruction regex was discarded. The replacement adds
no regex. It validates the batch count header, blank-line envelope boundaries,
and the actual number of complete process notices. It passes each notice through
the existing Desktop-derived parser. The instruction paragraph is never used to
classify the message and is not included in the displayed results.

One compact notice shows the batch count. Output contains every process status
and result, including failures. The shared projection covers saved history,
search, and edit/regeneration eligibility. Stored rows and IDs are unchanged.
Quotes, incomplete batches, count mismatches and assistant text retain their
ordinary presentation. Ambiguous text is left visible instead of guessing.

`tools/qa/generate_process_batch_fixture.py` calls the real installed
`ProcessNotificationBatch.render` and `format_process_notification` with 16
synthetic completion events. It writes `test/fixtures/process_batch.json`.
It launches no processes and makes no model requests. The fixture includes a
failure, bracketed output, and multiple paragraphs.

The producer-generated regression failed before the replacement with
`Expected: process_notification; Actual: null`, then passed after it. All 80
targeted tests passed across batch parsing, phone/tablet rendering, history,
search and saved-message actions. Tests also vary the instruction paragraph
to verify classification does not depend on its wording.

This remains recognition of a text-encoded protocol. The backend supplies no
batch type, so there is no type-only solution for those rows. A producer change
would be needed to remove that dependency. The backend remains unchanged.

## Release verification

The 2.36.3 release checkout passed static analysis and all 1,603 unit/widget
tests, with 10 skipped. The existing personal release script built and verified
the signed ARM64 APK as `com.tarkilhk.hermes.android`, version `2.36.3`, code
`22202`, using the pinned Personal certificate. Test output is in
`build/process-batch-full-tests.log`; build verification is in
`build/process-batch-release.log` in the selected release checkout.

The phone was not connected over ADB and no wireless ADB service was discovered.
The APK was prepared for installation; physical-phone verification is pending.
