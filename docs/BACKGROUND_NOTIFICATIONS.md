# Background notification delivery

Current decision, 2026-09-14: **Firebase delivery is dropped**, not an outstanding
milestone. The older proposal below is historical research. Existing local alerts
remain selected; sparse real alerts are being investigated. Permission/channel
checks passed, but live-event coverage currently depends on loaded chats. See
[current findings](ADMINISTRATION_ROADMAP.md#notification-findings).

Owner correction, 2026-09-12: **No Hermes backend modifications.** Any patch
contracts or deployment instructions described below are rejected experiments,
retained only as research. They were never deployed. Use existing Hermes APIs;
features requiring those invented contracts are deferred, not delivered. Do not
configure a new Hermes sender or deploy patches based on this document.

Selected scope: D26-D27, M01, R16, R17, S12 and M09. Updated 2026-09-12.
Hermes owns work and pending input. A notification points back to that work;
opening it must refresh the original authenticated server session.

## Current implementation

The app has local completion/input notifications, independent switches and an
optional chat-title preview. Its native notification callback already handles
warm taps and app launches, then resolves the original saved connection and
checks its current identity before opening the profile/chat.

The 2.27.1 client correction retries failed startup initialization before a later
alert or the explicit permission/test action. Concurrent callers share one
attempt, and a successful initialization reads the launch notification once.
Android notification IDs come from the original chat's serialized ownership key
using a deterministic digest. These corrections do not establish delivery while
Android has terminated the app. All 24 focused checks and 1,216 full-suite tests
pass, with four opt-in skips. Analyzer clean; signed Personal 21792 passed
certificate/package checks. Phone verification remains deferred.

Firebase configuration is not present in this repository, and the Firebase and
FlutterFire command-line tools were not found on the current PATH. The owner has
been asked whether to use an existing Firebase project or prepare a new one.
No project, billing setup or sender credential has been created. Version 2.28.0
adds the Firebase SDK and [the backend sender patch](../server-patches/0003-mobile-push.patch).
The client and patch are implemented; real delivery is not configured or
verified yet. App settings shows this distinction and provides Retry when a
configured build cannot register with a connection.

## Firebase setup needed

1. Select the owner's Firebase project, or create one under the owner's Google
   account. The approved design uses Cloud Messaging with the existing Hermes
   backend. Analytics, Cloud Functions, Firestore and other paid services are
   not prerequisites for this delivery.
2. Register the release Android application as `com.tarkilhk.hermes.android`.
   The installed product is **Hermes Personal**. The Gradle default and debug
   application identities differ, so configuration must explicitly target the
   release identity. Preserve the current signing key and upgrade path.
3. Generate the real Android Firebase configuration. Its project/app identifiers
   belong to client configuration; sender credentials do not. Decide separately
   whether a debug app registration is needed before configuring that variant.
4. Configure the trusted Hermes-side sender with access to that Firebase project.
   Keep its credentials on the backend. Do not put a service-account key in Dart,
   an APK, repository files or client configuration.

### Release build configuration

The Personal build script accepts `-FirebaseOptionsFile` pointing to a JSON file
with the public Android app identifiers:

```json
{
  "HERMES_FIREBASE_API_KEY": "",
  "HERMES_FIREBASE_APP_ID": "",
  "HERMES_FIREBASE_MESSAGING_SENDER_ID": "",
  "HERMES_FIREBASE_PROJECT_ID": ""
}
```

Fill these fields from the actual Firebase Android app registration. Empty
values leave background push unconfigured. `HERMES_FIREBASE_STORAGE_BUCKET`
is optional; this feature does not store files in Firebase. The script forwards
the file through Flutter's `--dart-define-from-file` argument. Keep the file
outside the checkout to avoid accidental project-specific commits. Never put
sender credentials in this file.

Without this argument, a Personal APK still builds and its existing local
notifications remain usable. The debug application needs its own matching
Firebase registration before testing real delivery on the emulator.

Firebase documents the project/app registration and generated Flutter options in
[Flutter setup](https://firebase.google.com/docs/flutter/setup). Its
[Admin SDK sending guide](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk)
describes sending to a registered device token from a trusted server environment.

## Verified Hermes dependency

The installed, unchanged backend source is revision
`8d79c2ff57bba4b07e5b37ed90387b16541aef53`. Inspection of `tui_gateway` and
`hermes_cli/web_routers` found no Firebase registration handler or sender.

Do not use the event name `notification.show` as a completion hook. In
`tui_gateway/agent_callbacks.py:101-105` it carries agent notices such as credits
or warnings. Work completion and input requests have separate events, including
`message.complete`, `approval.request` and `clarify.request`. Error completion
also needs to be distinguished from successful work.

`tui_gateway/server.py:573-596` stamps events for its replay ring and routes them
through the session's transport. Detached WebSocket sessions use a drop transport
at lines 196-213. An unrelated always-connected client is therefore not an
established global event feed. Do not claim a simple WebSocket relay would cover
all profiles and detached work without verifying that contract.

Patch 0003 adds authenticated `GET /api/mobile/push/status`,
`POST /api/mobile/push/installations` and
`DELETE /api/mobile/push/installations/{registration_id}`. Every request has an
explicit `profile` query and uses existing dashboard authentication. These
routes require deploying the patch; they are absent from the inspected stock
backend. Unconfigured builds do not make registration calls.

The sender configuration is host-wide while registrations are stored in each
profile's private `mobile_push.db`. The host configuration is:

```yaml
mobile_push:
  enabled: true
  firebase_project_id: YOUR_REAL_PROJECT_ID
  allowed_application_ids:
    - com.tarkilhk.hermes.android
  registration_max_age_days: 90
```

The backend uses Google Application Default Credentials with permission to send
FCM messages for that project. It sends through the HTTP v1 API from a bounded
worker queue. No database migration of Hermes work is involved. Unconfigured
senders do nothing. Retries are bounded; this is not a durable delivery outbox.

Eligible events receive one `mobile_push_event_id` on the existing WebSocket
payload. FCM reuses it as `event_id`. Sending does not depend on whether Desktop,
Android or no client currently owns the session transport. The worker reads
current registration/category/title preferences before sending and guards
invalid-token deletion against concurrent token rotation.

## Reuse on Android

Reuse `PluginTurnNotificationSink`, the existing notification channel and the
authenticated opening path in `HermesAppState`. Keep routing separate from the
message body. A title, arbitrary URL or current visible profile cannot identify
the destination.

Hermes sends high-priority data-only messages. Foreground and background Dart
handlers both use the existing local notification sink; Android does not also
auto-render a notification payload. The receiver rechecks current local
categories, preview preferences and secure connection ownership before showing
an alert. Notification taps use the existing authenticated chat-open path.
See [receiving messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

A bounded list of 64 delivery IDs prevents ordinary WebSocket/FCM duplicates.
Calls are serialized within each isolate and reload preferences before claiming
an ID. SharedPreferences is not a cross-isolate transaction, so simultaneous
claims during a foreground/background transition can still race. Both paths
use the same native notification ID to replace the same event. This does not
promise exactly-once notification sounds or delivery.

Firebase Messaging auto-init is disabled in the Android manifest. The app
requires the explicit Enable and test notifications action before token setup;
including the SDK or adding build configuration alone does not request a token.
Token and preference changes are serialized so a later change is not lost while
registration is in flight. Connection edits/removal attempt cleanup with the
previous credentials. Offline cleanup can fail; stale owners are rejected
locally and the server expires inactive registrations.

Registration must handle token changes, removed connections and changed access.
The sender should remove invalid registrations and avoid sending stale alerts.
See [registration-token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens).
Persist only the installation/delivery configuration needed for this flow,
alongside existing device settings. Do not add a local conversation database.

The 2.27.2 tap handler shares the latest pending open for the same target and
reuses a live notification-opened screen for that connection. The screen follows
the controller's current profile and chat. A later tap refreshes from Hermes;
closing the route removes its record, and a failed open remains retryable.
Only the latest requested target can finish opening, including rapid A-B-A
switches and slow cold initialization. This uses temporary navigation state,
not a saved list of opened chats. Eight routing widget tests and all 33 combined
notification checks pass. The full suite passed 1,224 tests with four opt-in
skips; analyzer clean. Signed Personal 21802 passed certificate/package checks.
Native cold/warm taps and live server behavior still need phone verification.

## Completion checks

- Synthetic tests cover initialization retry, stable IDs, original-owner routing,
  duplicate deliveries and removed or changed connections.
- A configured device receives completion and input alerts across profiles while
  locked, backgrounded and normally terminated by Android.
- Taps refresh the original server session after cold and warm launches.
- Permission denial, offline delivery, token changes and stale/duplicate events
  have explicit outcomes. Android force-stop remains a platform limit.

The owner is currently away from home, so wireless installation and live phone
checks are deferred. Unit tests and a signed APK do not complete these checks.
