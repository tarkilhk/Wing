# Supervision and queues — 2026-09-12

Current controls use the [held-slide composer selector](COMPOSER_ACTION_GESTURE.md).
The initial delivery below predates that interaction. Queue now waits for an
in-flight submission to finish before taking its draft or attachments.

This delivery covers D05, D07, D08 and D09 from the selected product plan. D06 approval controls shipped with the conversation foundations. Desktop contract evidence and backend gaps are recorded in [mobile delivery checks](research/MOBILE_DELIVERY_CONTRACTS_2026-09-11.md).

## Delivered behavior

- Activity discovers ongoing sessions independently in each profile on the current connection. Rows retain their original owner. Failed profiles are reported separately; a failed refresh does not present stale rows as current. Missing titles use a short session ID, with at most one metadata page fetched per profile.
- Sudo, secret and vault requests use dedicated forms and exact response methods. Expiry clears only the matching request; duplicate submissions are guarded. Credentials are not saved in drafts, logs or conversation messages.
- Completion and attention notifications have independent switches. Chat titles are optional and off by default. A permission-and-test action sends a synthetic notification; notification taps retain their existing host/profile/chat routing.
- Message actions, also reachable by holding Send/Stop, offer Queue and Steer without changing the normal button action. Queues hold unsent messages scoped to the original chat and saved in the existing draft store. The initial release queued text; 2.27 adds attachments as described below. Users can review/remove entries and explicitly resume a paused queue.
- Queues submit one item at a time after a completed turn. Sending a queued item preserves separately typed text and attachments. A persisted paused marker precedes submission, so an acknowledgement lost during a restart cannot cause an automatic repeat. Stop, failure or uncertainty pauses the remaining work. Steer checks the server's queued/rejected result and preserves rejected text.

## Verification

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: 921 passed, four opt-in integration tests skipped.
- Focused checks include partial Activity discovery and original ownership, request identity/expiry, six sensitive-form widget tests, notification settings, queue order/restart/uncertainty/stop/resume, and composer action sheets at large text sizes.
- Release source: Personal `2.1.4+2147`, ARM64 code `21472`. Build/deployment result is recorded in the delivery sequence.

No dependencies changed. This delivery reuses the existing gateway, draft store,
notification service and submit path. The maintained [changelog](../CHANGELOG.md)
records each release milestone, including this initial delivery. No public APK
release is implied.

## Remaining limits

The pinned Desktop source and mock-backed tests establish client behavior; they do not verify the owner's deployed gateway. That live gateway was unavailable from the local Desktop test setup. End-to-end sensitive responses and notification permission/tap behavior still need phone/backend verification.

Hermes continues accepted work independently, but the phone must be connected to drain its unsent queue. Opening a chat refreshes server state before draining a restored queue. Reliable terminated-app notifications remain D26/D27; no Firebase integration was added. The inspected resume response does not expose pending sudo/secret/vault metadata after process death.

Attachment queueing was outside the initial slice and is delivered in the
follow-up below. Local answer-version schema changes remain excluded;
conversation history and execution remain server-owned.

## Attachment-bearing queues, 2.27.0

The selected Q11/Q03 follow-up matches Desktop's text-and-attachment queue.
**Queue for the next turn** moves the current text and staged files into one
queued entry. Attachment-only entries are supported. Steer remains text-only.
The next draft stays separate, and saved text-only queue entries still restore.

Each staged file belongs to the composer or one queue entry. Queueing transfers
the existing references without copying files. Upload and submission reuse the
normal attachment coordinator and profile-scoped send path. Uploaded references
are saved before continuing, and the paused marker is saved before submission.
A failed upload or uncertain acknowledgement retains the queue for review.
Reopening the app cannot automatically repeat an uncertain submission.

The cache is removed only after successful durable queue removal, either after
an acknowledged send or an explicit Remove. Deleting a chat also clears its
composer and queued file caches after deleting the server chat and saved draft.
Failed local writes preserve the queued work and newer composer edits. Removal
targets entry identity, so identical text does not identify the wrong file.

All 108 focused checks passed. Full suite: 1,209 passed, four opt-in skips.
Independent review found no remaining issue. Checks cover attachment-only entries,
upload failure, lost acknowledgement and restored references, delayed writes with
newer typing, duplicate entries, cache cleanup and removal as a turn finishes.
Analyzer clean. Signed Personal 2.27.0 / 21782 passed native compilation and
certificate/package checks. Phone installation and live upload/queue QA remain
deferred while the owner is away from home. The client
must be connected to drain its unsent queue; background server execution and
the later FCM milestone remain separate.
