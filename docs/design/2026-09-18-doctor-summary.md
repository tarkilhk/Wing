# Doctor diagnostic summary

The Doctor result turns the final report below Hermes' horizontal divider into
a findings list. A compact warning icon and “3 issues found” heading lead, with
the observation time below in metadata text. Findings occupy one Studio group
with thin separators, semibold titles and muted supporting details. Detailed
checks and the CLI repair tip remain in the Diagnostic output disclosure.
Successful process completion no longer competes with reported issues.

The initial plain-text presentation was rejected by the owner after phone use.
For the revision, two arrangements were considered: a large count card followed
by separate issue cards, or a compact heading followed by one divided group.
The divided group avoids repeated framing and keeps the actual findings dominant.
The page uses Studio's navy/cream canvas, raised surface, border, muted text and
semantic warning/success tokens. Roboto title/body/metadata roles establish
hierarchy; monospace is reserved for raw output. No decorative numbering is added.
Refresh result is a 48 dp app-bar action; completed results do not show a
misleading Check progress button. Running and unavailable outcomes retain progress
access. All findings and details remain selectable.

The parser strips terminal color codes, extracts text after the final 60-character
divider, and excludes reports before the latest action-start marker. Numbered
findings become rows, with em-dash guidance or npm vulnerability counts separated
as supporting detail. Unknown finding wording remains intact. The returned
finding count and sequence must match the report before rendering it. While a
run is active, no final diagnosis is displayed. Missing/incomplete reports keep
the operation state and raw output available; no successful diagnosis is invented.

## Stock Hermes verification

Inspected upstream HEAD `64ea66b03d44ead9ffea48161132e5deca5d255a` on
18 September 2026 (local date):

- [Doctor endpoint](https://github.com/NousResearch/hermes-agent/blob/64ea66b03d44ead9ffea48161132e5deca5d255a/hermes_cli/web_routers/ops.py):
  `POST /api/ops/doctor` takes no request parameters and runs only `doctor`.
- [Action status](https://github.com/NousResearch/hermes-agent/blob/64ea66b03d44ead9ffea48161132e5deca5d255a/hermes_cli/web_routers/actions.py):
  status returns `running`, `exit_code`, `pid` and bounded log `lines`.
- [Doctor report](https://github.com/NousResearch/hermes-agent/blob/64ea66b03d44ead9ffea48161132e5deca5d255a/hermes_cli/doctor.py):
  `_print_summary` prints a 60-character `─` divider followed by findings or
  “All checks passed!”. The CLI supports `--fix`.
- [Hermes Console](https://github.com/NousResearch/hermes-agent/blob/64ea66b03d44ead9ffea48161132e5deca5d255a/hermes_cli/console_engine.py):
  Doctor is explicitly registered without auto-fix and passes `fix=False`.

The server does not expose Doctor repair through these interfaces. No repair or
copy-command button is added.

## Ask Hermes about a finding

On 19 September 2026 the owner selected an individual **Ask Hermes** action at
the bottom right of each finding row, using the shared square-pen icon and a
Studio text button. This supersedes the earlier diagnosis-only scope. The
findings remain selectable in one divided group; there is no page-wide action.
The selected design was compared with page-wide inline, bottom-anchored and
quiet-row alternatives before the owner requested per-finding actions.

The action captures the selected connection/profile, creates an independent
profile chat (without inheriting the last browsed project), and saves an editable
local draft. It focuses on the selected finding, includes Doctor's recommendation
when present, includes the available diagnostic output, and asks Hermes to explain
the likely cause, propose a solution, discuss data-loss risks and verification,
and ask for missing information. It explicitly says not to change anything or
run repair commands yet. Nothing is sent until the user sends the draft.

All finding actions and rerun are disabled during creation. Errors leave the
report available for retry. A profile change while creating the chat leaves the
draft with its captured owner; leaving the page does not navigate back later.
Existing drafts and chats are preserved. Pending chat creation does not rerun
Doctor or invoke any repair operation.

Verified current upstream main on 19 September 2026 at
[`d99226015dccf0716a6c3efc7d77aca753007b80`](https://github.com/NousResearch/hermes-agent/commit/d99226015dccf0716a6c3efc7d77aca753007b80):

- [`session.create`](https://github.com/NousResearch/hermes-agent/blob/d99226015dccf0716a6c3efc7d77aca753007b80/tui_gateway/contracts/sessions.py)
  accepts the profile via `ProfileParams` and returns runtime and stored session
  identities. The initial prompt is a Wing composer draft, not seeded transcript
  content or a submitted model request.
- [`ProfileParams`](https://github.com/NousResearch/hermes-agent/blob/d99226015dccf0716a6c3efc7d77aca753007b80/tui_gateway/contracts/common.py)
  carries the explicit canonical profile name.
- [`Action status`](https://github.com/NousResearch/hermes-agent/blob/d99226015dccf0716a6c3efc7d77aca753007b80/hermes_cli/web_routers/actions.py)
  caps output at 2,000 lines and 256 KiB. Wing now requests 2,000 lines for Doctor
  as it does for security audit. The owner accepted that output can be truncated.

Implementation is entirely in Wing and uses unmodified upstream Hermes.

## Validation

Doctor tests cover colored output, appended logs, incomplete findings, running
operations, retained results after read errors, and disclosure/refresh controls.
Rendered screens are inspected in light and dark themes at 390 dp / normal text
and 320 dp / 200% text, including scrolled action access, clean diagnoses and
errors. This verification uses client fixtures; no repair is performed.

`test/doctor_chat_test.dart` checks selected-profile creation, per-finding prompt
content, retained logs, editable composer handoff, preserved existing drafts,
duplicate-tap prevention, profile switches during creation, failed creation,
retrying a saved draft after navigation failure, leaving the screen, and the
Health-to-chat route. `test/doctor_diagnostic_page_test.dart` captures the enabled,
pending and error states in both themes at normal and 200% text. Captures are in
`build/doctor-preview/` when run with `CAPTURE_DOCTOR=true` and
`CAPTURE_FONT_DIR` pointing at the Flutter SDK's `material_fonts` directory.
Related chat-controller, draft-recovery, project-action, administration-repository,
runtime-health and security-audit tests also pass, as does `flutter analyze
--no-pub --fatal-infos`. These are fixture-based checks, not a deployed-device or
live-model acceptance run.
