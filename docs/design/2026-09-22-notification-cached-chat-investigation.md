# First-question failure: phone trace and cached-chat reproduction

**Final verification, 23 September:** the corrected saved-cache path passed on
the physical phone: first useful notification before opening, Review, same-slot
3→2→1, accepted answers and cleanup. Both focused bug-fix retests are complete.
[Final live result](2026-09-23-notification-final-live-result.md). Earlier pending
verification statements below describe the historical investigation stage.

This investigation follows the second failed live retest on build 2328. The
previous stock-empty-approval race was a real fixture failure, but it did not
explain the full device path. The first delivery problem stayed open until this
investigation captured the missing branch on the actual phone.

## What the previous work missed

The supposedly cold test started with empty reading storage. The physical phone
had used the chat previously and restored a saved reading copy on launch. These
are materially different states even though neither test opens the chat after
restarting. Fixing a downstream alert race cannot help when an earlier guard
prevents the request from being read at all.

Checking stock API definitions was necessary but insufficient: the fixture also
had to model the local persisted state and the production path through it. The
phone's incorrect Idle label was evidence of a failure before notification
rendering; it should have been investigated alongside the missing notice.

## Actual phone evidence, before changing behavior

Installed a signed production-package copy of build 2328 with temporary
compile-gated tracing only. The trace recorded statuses, counts, boolean guards
and process-local identity hashes, excluding question text, credentials, titles
and raw chat/connection identifiers. No Hermes behavior or configuration changed.

The startup trace showed saved chats with `offline=true`, `status=idle`, and
runtime identity equal to their durable chat identity. Hermes' active rows used
a different runtime identity for the same durable chat.

In the user-driven WING-TRACE-INPUT run:

- Monitoring observed working and the phone was automatically backgrounded.
- **23:30:38.605 SGT:** the real `session.active_list` row reported `waiting`,
  previously `running`. Its saved chat remained offline/idle, not opening, with
  a different runtime identity.
- **23:30:38.761:** ownership lookup found exactly one matching profile.
- The next trace entry was **`input-skipped-existing`**: the offline cached
  object already occupied the durable chat slot. The request resume path was
  never entered.
- **23:30:40.604:** monitoring stopped and the observed chat notification set
  was empty. No theory about Android dropping a posted notification is needed.

A complete one-shot log read captured the final decision; the streaming reader
had temporarily buffered its last line. Keep that capture detail distinct from
any application defect. Private traces and diagnostic APK remain under
`/tmp/wing-input-diagnosis-live/`; raw device evidence is not committed.

## Confirmed cause

`_restoreReadingSnapshot` reconstructs cached chats using their durable session ID
as a placeholder runtime ID. `_loadedNotificationChat` deliberately matches live
runtime plus durable ID, so it correctly does not treat this offline placeholder
as an attached live chat. But `_loadNotificationInput` then sees the occupied
durable-ID slot and returns unconditionally. Neither path takes responsibility
for attaching the cached chat.

The cached object's Idle status and absence of pending input also explain the
list label. Global reconciliation updates known activity rows, while this list
started before work with no corresponding activity row. Opening the chat manually
performs the missing attachment and immediately reveals the questions.

## Reproduction and target correction

`test/profile_cached_notification_test.dart` writes a real WorkspaceSnapshotStore
before creating a fresh controller, then drives working → waiting without opening
the chat. Before the fix, it fails with **0 resume calls, 0 notices, Idle status,
and monitoring stopped**, matching the captured phone path.

```sh
flutter test --no-pub test/profile_cached_notification_test.dart --reporter expanded
```

Red evidence: `/tmp/wing-cached-input-red.log`. Current stock Hermes was verified
at `95f20517c25ee418da5337f4ead347008baaa2b3`: pending requests remain in active
rows as `waiting`; runtime `id` and durable `session_key` are distinct identities.

The correction must adopt the existing eligible offline object under the verified
owner, preserving its transcript and references. A failed or mismatched resume
must restore the old binding only if nothing newer has happened. User navigation
and newer live events must win over delayed reads. No new polling, backend
changes, compatibility paths or watcher-lifetime extension are needed.

## Fix and validation

The corrected path reuses the cached object and provisionally binds the verified
live runtime. It restores the old runtime/offline state after a failed read only
if no event or navigation has overtaken it. Successful hydration publishes the
new input before yielding to unrelated refreshes. A resolved request leaves the
cached transcript intact. Temporary trace code is removed from the source.

- Ten persisted-cache tests cover delivery, failed reads/retry, runtime/session/
  profile mismatch, newer live requests overtaking successful or failed reads,
  resolution during resume, concurrent user opening, and ambiguous ownership.
- **39 focused tests passed**, including existing notification coverage and
  monitoring lifecycle tests.
- Android 16 emulator, exact same saved-cache fixture before/after: the old code
  fails with no first notification, Idle/offline cached chat and zero resume
  calls (`/tmp/wing-cached-native-red.log`). The fixed code posts one fresh native
  notice containing 3 questions, the real first question/options and Review;
  preserves the same cached object/history; binds its live runtime; and stops
  monitoring (`/tmp/wing-cached-native-green.log`).
- Visual inspection of the actual Android notification confirms the count,
  question, choices and Review are visible at the emulator's enlarged font size.
- Analysis is clean; 28 release-tooling tests and source version check pass.
- Complete Flutter suite: **2,698 passed, 12 skipped**.
- Signed production **2329** verified for the pinned certificate, production
  package, ARM64-only release, non-debuggable flag and version. Data-preserving
  installation succeeded; physical phone readback confirms **1.0.1 / 23292**.
- APK SHA-256: `d354d43a09a106e5bce0660a049637981e9db2d4cafe2f545908701f2b0becd2`.
- Temporary tracing is absent from source and the installed release; capture
  processes and temporary emulator are stopped. The phone was not navigated
  after installation while availability confirmation remained pending.
- A fresh fixed-phone first-question pass is still pending. The root-cause trace
  was captured before the fix; Android before/after validation used the isolated
  fixture. These distinct evidence types are not presented as interchangeable.

The traced request was left unanswered when the phone was showing the Remote app
and availability confirmation had not arrived. No answer was fabricated or sent
from another client. Its final backend state was not verified during that pause;
check for a pending form before starting the final live retest.

