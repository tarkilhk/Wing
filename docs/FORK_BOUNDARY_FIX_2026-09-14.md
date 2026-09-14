# Fork validation after compaction

The reported toast was emitted after `session.branch` returned a new durable
chat ID. Android retained the child but rejected its copied-message comparison
before navigating to it. Refreshing Chats therefore revealed the created fork.

The installed official Hermes source at
`e16f686706b1e0d5334fd1ae82190058d2a19694` exposes different histories:

- `session.history` in `tui_gateway/methods_session.py` calls
  `get_messages_as_conversation` without `include_compacted`. Its default is
  false in `hermes_state_messages.py`.
- `session.branch` uses `_branch_source_history`, which reads the persisted
  display transcript through `get_resume_conversations`. That transcript includes
  archived turns retained after compaction.
- The RPC response also projects message text for display. It is unsuitable for
  comparison against unprojected saved content.

Android previously counted saved rows for the fork request but compared the
returned child against the shorter RPC history. A deterministic controller test
with two archived rows reproduced the exact reported error after child creation.
The user's private conversation was not read, so its particular compaction state
has not been independently confirmed.

Forking now resolves the selected saved answer and expected transcript from the
paginated REST history with `include_compacted=true`. It reads the child's saved
history through the same API and compares roles, text, and row count before
opening the fork. Regeneration continues using its existing RPC history flow.
Missing, changed, or extra copied messages still fail validation. That error now
explicitly says the fork was created and remains available in Chats.

## Verification

Before the fix, this command failed with the exact screenshot toast:

```powershell
flutter test --no-pub test/answer_versions_test.dart --plain-name 'fork opens after copying archived turns omitted by RPC history'
```

After the fix, 81 tests passed across `answer_versions_test.dart`,
`profile_composer_actions_test.dart`, `profile_saved_history_test.dart`,
`profile_history_search_test.dart`, and `profile_conversation_ui_test.dart`.
Six new cases cover archived history, an archived selected answer, a different
RPC display projection, and missing, extra, or changed saved copies. Existing
checks cover pagination, hidden notices, stale answers, navigation, and
regeneration. `git diff --check` passed for the changed code and tests.

Final full static analysis passed after the concurrent notification task removed
its unused import. This fix ships in Personal 2.34.3+2214, following the
notification update in 2.34.2. No backend code or server conversations were
changed during diagnosis.
