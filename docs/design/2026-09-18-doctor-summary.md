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

The server does not expose Doctor repair through these interfaces. The owner
confirmed that this change should provide only the clean diagnosis when the
official server lacks repair support. No repair or copy-command button is added.

## Validation

Doctor tests cover colored output, appended logs, incomplete findings, running
operations, retained results after read errors, and disclosure/refresh controls.
Rendered screens are inspected in light and dark themes at 390 dp / normal text
and 320 dp / 200% text, including scrolled action access, clean diagnoses and
errors. This verification uses client fixtures; no repair is performed.
