# Local alert coverage

## Scope

Use existing Hermes events and APIs. No backend modifications, Firebase setup,
or push delivery are part of this change. The app process and its authenticated
connection must remain alive for local alerts.

The reproduced client gap is that `sessions.changed` was ignored. Direct
completion and input events only reached chats loaded by the Android controller.
An independent Desktop client could therefore run a task that Android never
considered for an alert.

The server's general change event contains no chat or completion payload. Its
`session.active_list` response supplies runtime IDs, durable session IDs and
`starting`, `working`, `waiting` or `idle` states. Exact session searches under
the discovered profiles establish ownership. The app must not activate a
server-wide profile or attach to every running chat to receive notifications.

## Acceptance checks

| Check | Result |
| --- | --- |
| Regression test reaches the missing-alert code path | Reproduced before the fix: `sessions.changed` caused zero live-status reads. |
| Unopened task requests input and then finishes | Passed. Deterministic transitions and an actual Hermes `clarify` request produced the expected attention and completion callbacks. |
| Opened chat's direct events remain independent of global reconciliation | Passed. Existing controller, notification routing, settings and delivery checks passed; the loaded-chat direct/global test emitted one alert. |
| Disconnect, failed reads, unknown status and missing runtimes produce no false completion | Passed. Focused cases remained silent; profile collisions and failed ownership reads also emitted no alert. |
| Real Hermes task started by an independent client in another profile | Passed. Producer used `android-qa-a`, observer stayed in `android-qa-b` without opening the chat. Real completion yielded exactly one correctly scoped callback. |

Validation on 2026-09-14: the combined run passed 106 checks in 32 seconds,
including two real-backend scenarios. An additional real clarification scenario
passed in 11 seconds. The final seven-test coverage suite passed after adding
explicit missing/unknown-status cases. This totals 109 distinct passing checks.
No APK build or phone test was part of this change.

The opt-in live check is `test/profile_notification_live_test.dart` with
`HERMES_TEST_PORT` set to the local dashboard port. It uses two production
controllers and an actual model turn in disposable QA profiles. It does not
inject a completion event or manually call the alert callback. The observer
never opens the producer's chat. The check verifies the callback destination
and count; it does not establish Android notification delivery after process
termination.

## Delivery limits

- Initialization takes a silent status baseline; it does not notify about old
  completed work. Only active/waiting runtime state is retained in memory.
- Hermes coalesces general session-change events. An entire short turn between
  snapshots can still be missed. A runtime finalized before its idle state is
  observed is not reported as completed.
- Failed reads or a disconnected connection reset the baseline. The next
  successful snapshot does not invent what happened during the gap.
- Global status is limited to runtimes visible to that Hermes gateway process.
  The inspected contract does not establish child-only completion or work in
  unrelated gateway processes.
- An observed transition to idle means the turn settled. This global status
  does not distinguish success, cancellation and failure. The notification
  therefore says the chat finished; opening it loads the actual result.
- Android must permit notifications and keep the app process running. These
  changes do not promise delivery after process termination.

## Separate roadmap and QA labels

- Answer versions means browsing regenerated alternatives to one prompt across
  clients. Ordinary history sync, Regenerate and Branch already exist. A shared
  alternatives carousel has no verified backend contract.
- Child-only activity means an idle parent with a still-running delegated agent.
  The inspected global session rows do not report those child counts. This is
  distinct from displaying the roster in an opened chat.
- Non-default profile loops have a reproduced routing mismatch between `/loop`
  and scoped structured controls. Testing two profiles exposed that mismatch;
  it does not justify repeating every behavior under every profile.
- Vault QA means actual Hermes browser requests to unlock a vault, save a login,
  or supply a code. The forms exist, but the local browser failed before emitting
  a request. A configured external vault was also unavailable.
- Approval choices include Once, Session, Always and Deny when offered by the
  server. Session and Always remember the applicable approval rule, not blanket
  permission for all actions. The previous live acceptance covered Once and
  Deny; the other options are implemented but were not exercised there.
