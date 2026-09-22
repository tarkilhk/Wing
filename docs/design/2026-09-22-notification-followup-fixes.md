# Notification fixes after the 22 September retests

Scope: the initial generic input notification (partial R1) and unread reply
restoration after Android force-stop/relaunch (failed R5). Historical live
outcomes remain in the [retest results](2026-09-22-notification-retest-results.md).
The [two focused live retests](2026-09-22-notification-followup-retests.md)
ran on the updated phone: **A failed; B partially passed**. See the
[live outcomes](2026-09-22-notification-followup-live-results.md): cold input was
not delivered; restored replies returned correctly but did not clear on reading.
The automated evidence below does not override those failures.

## Initial structured input

The global activity path detected that an unopened chat needed input, but posted
an empty input notice without obtaining its structured request. Wing now reads
the owning stock `session.resume` snapshot with `omit_messages`, then uses the
existing request state and notification rendering. No chat opening or transcript
download is required. Question counts, text, choices and Review are available
on the first notice when the stock request read succeeds.

The client validates the runtime, durable session and profile owner. New live
events and navigation take precedence over an older in-flight snapshot. A failed
read does not invent actions; a later existing activity invalidation can retry.
No polling loop or background monitoring lifetime extension was added.

Upstream stock Hermes was inspected at
`e2f8a0731bf26e95b31e35d73e71e183a1045b81`. Its lightweight resume response exposes
current `open_requests`, running state and runtime/durable session identities.
No backend source, configuration or deployed version was changed.

## Unread reply restoration

Wing already persisted the reply and its posted revision. A new app process
mistook that saved rendering state for evidence that Android still displayed the
notification. Android removes the native notification on explicit force-stop.

Startup now drains saved native swipe-dismissals, validates current saved
connection identities, and silently redraws previously posted unread notices.
The reply keeps its chat slot, content and revision. Read/dismissed notices and
silent baselines are not recreated. Current notification/privacy settings apply;
removed connections or changed credentials cannot restore their old notices.
Restoration does not submit or repeat approval decisions.

## Regression evidence

Before the fixes, focused tests reproduced missing first-request content and
missing cold-start restoration. The isolated Android QA app also reproduced the
real force-stop failure: one reply existed before stopping, and none returned
after launch. Raw local logs: `/tmp/wing-sept22-red.log` and
`/tmp/wing-native-restore-red.log`.

Validation for build **2327**:

- The two original regressions and the delayed navigation race failed before
  their guards/fixes and pass afterward. All **95 focused tests** pass.
- Complete Flutter suite: **2,687 passed, 12 skipped**. Code analysis clean;
  **28 release-tooling tests** pass; source version check passes.
- Real Android 16 emulator with the isolated QA package:
  `scripts/test_native_notification_restore.py --serial emulator-5554` passes
  same-ID/same-text restoration after explicit force-stop, native silent/only-
  alert-once flags, and an actual swipe dismissal remaining absent after relaunch.
  The initial dismissal gesture was too short; the harness now swipes across the
  notification width. This was a test gesture correction, not another app fix.
- `scripts/test_native_notification_counts.py --serial emulator-5554` passes
  counts **3 → 2 → 1** in both Android text layouts and hidden-preview privacy.
- Signed ARM64 production APK passes package, architecture, non-debuggable,
  version **1.0.1 / 23272**, and pinned signing certificate checks. SHA-256:
  `be514fc658fa1f9dbf4db2f33979d1dcc687402b46ebe9f534ad6e5f41074968`.

Client-fixture passes do not substitute for the two stock-Hermes live retests.
Installation/readback is recorded in the [current status](2026-09-20-notification-test-status.md).

## Separate follow-up

The New activity shortcut made the latest answer visible but required another
full-bottom scroll before clearing its notification. The previously accepted
bottom rule passed. This shortcut detail remains a separate UX follow-up and is
not claimed fixed by these two changes.
