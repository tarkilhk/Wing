# Notification resume durable identity

`ARCH_RESUME_DURABLE_IDENTITY` protects the two actual captured resume workflows
`ProfileWorkspaceController.loadNotificationApproval` and `_loadNotificationInput`
in the canonical controller library and its actual parts. They must not read raw
literal `session_key` or `stored_session_id` indexes, including nested bodies.
Use the captured gateway's validated durable-ID projection. Active-list decoding
in other methods and homonymous declarations in other libraries/classes remain
valid. Missing/ambiguous declared scope is input exit 2.

Current stock Hermes `1fd75357e92d217199e04849b819e7de10f35e1d` returns
`session_key` from the persisted `_resume_response` and `stored_session_id` from
`_resume_live_unpersisted`. The original two checks accepted only the first form.
The projection validates the captured profile and runtime using `_ownedSession`,
rejects missing/malformed/empty or conflicting durable IDs, and preserves the raw
reply. Runtime `session_id` never substitutes for a durable ID. Both stock forms
are current protocol mapping, with no legacy alias or fallback.

```sh
dart run tools/architecture/rules/resume_durable_identity.dart --strict
dart run tools/architecture/tests/resume_durable_identity_test.dart
```

This finite parsed rule prevents direct literal wire-key recurrence at these
exact ownership sites. It does not resolve symbols or arbitrary map/dataflow,
computed/aliased keys, delegated helpers, renamed workflows, response validation,
ticket/generation fences or runtime lifetime. Existing meaningful notification
controls own asynchronous semantics; the actual current stock response cases
in `profile_notification_coverage_test.dart` own the mapper/adoption behavior.
The rule deliberately does not demand one helper spelling or ban `session_key`
globally. Root owns execution, CI registration and production acceptance.
