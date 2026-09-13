# Attachment and regeneration parity

Current official source checked on 2026-09-13 at
[`b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a`](https://github.com/NousResearch/hermes-agent/commit/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a).
This replaces the earlier assumption that Android's attachment and regeneration
flows already matched Desktop. No Hermes backend code, configuration or deployment
was changed.

## QA-018: attachments

Desktop's [attachment uploader](https://github.com/NousResearch/hermes-agent/blob/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a/apps/desktop/src/app/session/hooks/use-prompt-actions/index.ts)
sends remote images using `image.attach_bytes` with `content_base64` and
`filename`. The returned image path identifies a pending image on that live
session. Generic files use `file.attach` and contribute its returned `ref_text`
to the prompt. Desktop's [submit code](https://github.com/NousResearch/hermes-agent/blob/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a/apps/desktop/src/app/session/hooks/use-prompt-actions/submit.ts)
puts file references before the visible message and supplies a question for an
image-only submission.

Android 2.31.8 follows those calls. Accepted images are not uploaded twice when
a later file fails. Their cache remains until submission succeeds, so a new
runtime can upload again. Removing an accepted image calls `image.detach` so it
cannot silently accompany the next turn. Unsent draft records retain the image's
path and owning live session; those fields reset when moving to a new session.

The original text-file content failure remains separate. Current official
[`prompt_attachments.py`](https://github.com/NousResearch/hermes-agent/blob/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a/tui_gateway/prompt_attachments.py)
still stages remote file bytes beneath the profile home attachments directory
and returns an absolute reference when that directory is outside the session's
working directory. [`cli_chat_turn_mixin.py`](https://github.com/NousResearch/hermes-agent/blob/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a/hermes_cli/cli_chat_turn_mixin.py)
expands references with the working directory as the default allowed root.
[`context_references.py`](https://github.com/NousResearch/hermes-agent/blob/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a/agent/context_references.py)
rejects a resolved file outside that root. The current `file.attach` contract
offers no upload destination parameter. Moving the reference before the text
does not make the path accessible. Do not claim that upload acknowledgement
proves file contents reached the model, or replace references with pasted file
contents to hide the failure.

A local fixture ran the unchanged staging, reference-path and path-resolution
functions from that pinned source, supplying only disposable workspace/profile
locations. Uploading a synthetic text file reproduced the exact outside-workspace
exception. An inside-workspace control resolved successfully. This verifies the
path failure independently of Android and makes no claim of a live Desktop GUI
test or a successful model read. The diagnostic script is tracked at
[tools/qa/reproduce_official_attachment_boundary.py](../tools/qa/reproduce_official_attachment_boundary.py). It reads the two linked official Python files from `build/official-desktop-qa`, preserving their repository-relative paths. Download them at the pinned revision above before running `python tools/qa/reproduce_official_attachment_boundary.py`.

## QA-019: regeneration

Desktop's [rewind implementation](https://github.com/NousResearch/hermes-agent/blob/b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a/apps/desktop/src/app/session/hooks/use-prompt-actions/rewind.ts)
submits the selected question in the current session and truncates at its saved
user row. Android previously created a child session first. That extra copy
crossed the gateway's live/durable history reconciliation, where the recorded
attachment-bearing reproduction received error 4018. The exact differing
server text has not been established.

Android 2.31.8 regenerates in place. It reads current history, verifies the
selected message, and submits the fresh prompt row with the existing truncation
confirmation flags. Explicit Branch still creates a separate session. A
definite rejection restores the displayed conversation. A lost acknowledgement
uses existing reconciliation and never automatically resends. Unsent drafts
remain untouched.

Desktop rebinds cached survivor row IDs from the submit response. Android instead
refreshes saved history after completion and rechecks fresh history before every
answer action, so it does not need an additional survivor map. Both clients
resubmit the saved text projection without reattaching original image bytes.

## Verification

### QA-029: persisted attachment context

The local live retest exposed another client difference. On installed official
Desktop revision `e16f686706b1e0d5334fd1ae82190058d2a19694`, the unmodified
`apps/desktop/src/lib/chat-messages/hydration.ts` helper
`displayContentForMessage` removes the generated attached-context section,
restores missing references and avoids duplicating references already in the
visible prompt. `planReload` then resubmits that visible text. The earlier
conclusion that this required a new server field was incorrect; the hydration
step had been missed.

Android 2.31.9 ports that projection for saved user-message display, edit defaults
and regeneration submissions. Raw stored text and row IDs remain unchanged for
history validation and branch boundaries. No second conversation store or
backend change is needed. Assistant content is not stripped.

The isolated official preprocessor reproducer is
`tools/qa/reproduce_official_regeneration_context.py`. Replaying the expanded
prompt produces two attached-context headers and three copies of the file. A
plain prompt stays unchanged. The controller and rendering regressions both
failed before integration; the focused tests passed after it. The 2.31.9 live
retest returned the value found only in the file, preserved the unrelated draft,
and retained four history rows. The replacement prompt contains exactly one
attached-context section and one copy of the file contents. Evidence:
`build/qa029-fixed-history.json` and
`build/qa029-fixed-regenerate-complete.xml`.

The image-route regressions failed on the old client. The regeneration regression
failed because Android called `session.branch`. All 71 focused attachment,
draft, queue and answer-action tests pass after the changes. Live verification
and full-suite results are recorded in the [QA ledger](QA_SWEEP_2026-09-13.md).
These initial checks preceded the successful local live results below.

Automated result: 1,325 unit/widget tests pass after the release-version assertion
was updated, with four opt-in skips. Static analysis is clean. Signed 2.31.8 /
21932 is installed on the phone. Live tests stopped before submission because
the existing QA chats could not be opened, also observed on 2.31.7. Dashboard
authentication/provider checks passed; the session-open failure is unclassified
QA-028 in the ledger. Those initial phone checks did not establish a live pass.

The subsequent local-server emulator retest passed saved-chat opening,
content-dependent image and text delivery, and same-chat regeneration of the
text attachment. Earlier history and an unsent draft survived; saved history
contains exactly two user/assistant pairs with no child conversation. The
updated emulator interaction test also passes against isolated gateway data.
The original deployment's outside-workspace condition is not ruled out by a
passing local file path. The separate duplicate-context defect, QA-029, passed
its 2.31.9 live retest described above.
