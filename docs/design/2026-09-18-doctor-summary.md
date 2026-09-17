# Doctor diagnostic summary

The Doctor result displays the final report below Hermes' horizontal divider
immediately, in Studio body typography. Runtime scope and completion time stay
subordinate; detailed checks remain in the Diagnostic output disclosure. Process
completion is separate from the findings, so a zero exit code still shows issues.

Two layouts were considered: summary → output disclosure → progress action, or
separate Summary and Output tabs. The single page keeps the diagnosis visible
without a tab switch or a second navigation layer. It uses existing Studio colors,
sans body text, spacing and scroll behavior, retaining monospace for raw output.

The parser strips terminal color codes, extracts text after the final 60-character
divider, and excludes reports before the latest action-start marker. While a run
is active, no final summary is displayed. Missing reports keep the existing
operation state and raw output available; no successful diagnosis is invented.

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

22 Doctor and health tests pass, covering colored output, appended logs, absent
summaries, running operations, retained results after read errors, and disclosure
and progress controls. Rendered screens were inspected in light and dark themes
at 390 dp / normal text and 320 dp / 200% text, including scrolled action access.
Static analysis reports no issues. This verification uses client fixtures;
no live server operation or repair was performed.
