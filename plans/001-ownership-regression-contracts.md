# Ownership regression contracts

Execution ledger for phase 1 of the architecture program. These contracts describe
the corrected active paths; they do not claim the later architecture or device
acceptance gates have passed. Tests run in the ordinary host suite enforced by CI.

| Finding | Observable invariant and active regression | Prevention decision |
| --- | --- | --- |
| D01 delayed resume | Open, reconnect and queue resume cannot erase newer text/input, resurrect a completed turn, rebind a replaced runtime or publish an older concurrently started read. `test/profile_resume_freshness_test.dart` controls response/event ordering. | Behavioral guard: symbol/import analysis cannot determine which asynchronous response owns the current turn. The private resume ticket and captured owner/runtime/event facts fence publication. Independent usage observations must permit execution recovery. A superseded history failure must not fail current recovery. |
| D02 shared draft rollback | A failing save rolls back only the version it staged; subsequent edits, including editing away and back to the same text, survive. `test/profile_shared_draft_test.dart` injects held/failing durable writes. | Behavioral guard: persistence completion order and user edits require controlled I/O. Private draft revisions support the test; comparing text alone is insufficient. Files retained by newer drafts cannot be removed by the failed stage. |
| D03 completion persistence | A completion preserves the exact suffix/selection and survives controller recreation. `test/slash_commands_test.dart` exercises the real widget and durable draft owner. | `ARCH_VIEW_DRAFT_WRITE` forbids resolved `ProfileChat.draft` writes from views/presentation; unrelated same-name properties and controller commands are accepted. Its separate rule and semantic/CLI fixtures run through CI. Durable behavior remains a widget/store regression. |
| D04 acknowledged deletion | Confirmed server deletion immediately removes navigation/browser state. Cleanup failure never republishes the chat; retry performs only local cleanup and never another DELETE. `test/chat_browser_mutations_test.dart` injects cleanup failure. | Behavioral guard: a static ban on catching or awaiting cleanup cannot establish acknowledgement ordering. Cleanup waits for the chat's already scheduled draft writes before clearing storage. Restart retention of pending cleanup is a remaining phase-5 lifetime obligation; the current in-memory receipt does not establish it. |
| D05 task edit baseline | Name-only edits preserve fields changed elsewhere; editing the same field produces a conflict and retains user input. `test/scheduled_tasks_screens_test.dart` verifies the actual route; repository tests verify sparse updates. | Behavioral guard: user intent, opening baseline and fresh server values are semantic inputs. The complete edit-session owner and private baseline are phase-3 work. |
| D06 task ownership/uncertainty | Fresh scoped membership rejects a missing/moved task before dispatch. A lost/malformed acknowledgement cannot unlock automatic resend, including after restart or failed post-dispatch journaling. `test/scheduled_tasks_repository_test.dart` and `test/scheduled_tasks_controller_test.dart`. | Behavioral guard: remote ownership and durable write acknowledgement cannot be inferred from source shape. Predispatch review records are durable before sending. Stock Hermes has no atomic expected-owner condition; preflight cannot eliminate that race. See `001-task-regression-contract.md` for inspected stock revision and limits. |
| D08 reading cache | Cached hidden rows stay hidden; steering, reviews, delegation notices/results and optimistic attachment cards retain their display meaning. Cache grants no live input/decision authority. `test/reading_snapshot_message_test.dart`, `test/workspace_reading_snapshot_test.dart` and `test/workspace_snapshot_limits_test.dart`. | Behavioral guards exercise the actual projection, encoder, typed storage restoration and renderer. The bounded domain projection accepts only known passive fields, limits attachment count/metadata and excludes inline attachment bytes. An import guard protects its domain dependency boundary. |

Fresh independent reviews found two additional D01 counterexamples: unrelated
usage events wrongly rejected recovery, and errors from superseded history reads
escaped the publication fence. Both receive controlled-order regressions. Standard
analyzer diagnostics handle unused imports, redundant null assertions and syntax
lint issues; separate duplicate custom rules are unnecessary for those patterns.

Evidence is private/ignored under `build/architecture-program/`: original baseline,
red reproductions, focused greens, full batch suite and guard results. A batch is
accepted only after its final source passes analysis and affected/full tests;
this ledger is not a substitute for those checks. Later new findings extend the
ledger with their precise property, individual rule or reason static detection is
unsuitable, and deterministic regression.
