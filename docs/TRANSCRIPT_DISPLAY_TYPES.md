# Transcript display types

Verified against the installed official Hermes Desktop source at NousResearch/hermes-agent commit `e16f686706b1e0d5334fd1ae82190058d2a19694` on 2026-09-14.

Android previously rendered `async_delegation_complete` rows as ordinary user bubbles. Hermes uses the user role for model-facing deliveries as well as human messages, so the role alone does not determine presentation.

The client now follows Desktop's [`hydration.ts`](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/desktop/src/lib/chat-messages/hydration.ts) display projection:

| `display_kind` | Presentation |
| --- | --- |
| `hidden` | No transcript row |
| `async_delegation_complete` | Compact completion notice, optional count from `display_metadata.task_count`, result disclosure |
| `model_switch` | Model changed |
| `auto_continue` | Resumed interrupted turn |
| `personality_switch` | Personality changed |

Classification uses `display_kind`, not keyword matching against user content. The existing gateway-compatible `[System:` hidden-marker rule and steering/review presentation are retained. Unknown or missing types keep their ordinary presentation.

The delegation disclosure follows Desktop's producer-boundary parser and [`async-report.test.ts`](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/desktop/src/lib/async-report.test.ts). It extracts result/error bodies, handles batch task boundaries and cron output, and removes transcript-path footers. It never shows the delivery preamble or task goals. A malformed envelope has no result disclosure. Untyped user text is not parsed as a delegation event.

Both saved and refreshed history use the same renderer. Find in chat searches the projected notice/result instead of its internal delivery payload. Raw history, durable IDs, pagination offsets and model context remain intact. Existing typed-prompt checks keep timeline events out of Edit and regeneration prompt selection.

Regression coverage is in `test/internal_message_visibility_test.dart`: the screenshot's payload, history refresh, hidden-row grouping, display metadata as REST JSON or decoded maps, result boundaries, ordinary technical text and regeneration selection. This verifies the client against fixtures; it does not change the Hermes backend.

Validation passed: 66 affected transcript, search, answer, steering and activity tests, followed by 19 display/search tests covering the final phone/tablet layouts and search attribution. Targeted Dart analysis of the four changed production files and regression test reports no issues. The owner's request to test affected areas applies; the preceding release's full-suite verification is retained without another local full-suite or dependency-update run. There are no dependency changes.
