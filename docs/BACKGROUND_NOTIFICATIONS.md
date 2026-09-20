# Background notifications

Wing keeps its authenticated Hermes event connections running in an Android foreground service while at least one chat is working. The ongoing notification shows a live summary such as **Watching 3 chats · 2 working · 1 needs approval**. Firebase and server push registration are not required.

The monitoring indicator uses the **wing with circular arrows**; replies use
the plain wing, and input/stopped alerts add small type cues. Monitoring has its own notification
group, with a summary and the foreground-service notification, so Android does
not combine it with chat alerts. Both monitoring entries reopen Wing without
selecting a chat. Expand a chat notification group and tap the individual alert
to open its original chat. Android controls grouping and available status-bar
space; see [Android notification groups](https://developer.android.com/develop/ui/views/notifications/group).

The service retains the same Flutter engine and workspace controllers when the activity is backgrounded or destroyed. Reopening Wing attaches to that engine, preserving event subscriptions and notification tap routing while work continues. When no activity is attached and the last working chat ends, the engine can be released after its final notification is posted. It monitors connections opened in this app; it does not subscribe to every saved server or fix missing server events.

## Enabling monitoring

1. Connect to Hermes and enable Android notifications using **Enable notifications** (or **Test notification**) in app settings.
2. Monitoring starts automatically when a chat begins work while Wing is visible and at least one alert category is enabled. Idle chats do not start the service. There is no separate monitoring toggle; app settings show an action only when notification delivery needs attention.
3. If settings report battery restrictions, choose **Allow background activity** and approve Android's exemption prompt. This allows the authenticated connection and partial wake lock to operate during Doze. A foreground service alone does not exempt networking from Doze.

Monitoring uses additional battery. Its partial wake lock is held only while the service runs and is released when it stops. When no chats are working, the service stops after posting any final reply or question notification. Those chat notifications remain visible. Opening a question and answering it starts monitoring again when work resumes. Another working chat, queued submission or live child task keeps the service running; a temporary disconnect does not count as completion. Disabling both alert categories or revoking notification permission (reconciled on app resume) also stops the service.

Android force-stop, process termination, a reboot, lost connectivity and manufacturer restrictions can still interrupt delivery. Reopen Wing after the process is terminated. Work started from another client cannot wake a stopped Wing process; reopening Wing reconnects it. While Wing remains connected, global status reconciliation provides the unopened-chat coverage described below. The service deliberately does not restart without its live clients or display a monitoring notification for an empty process. Accepted Hermes work continues on the server.

Temporary network loss while the process survives uses [network continuity](design/2026-09-16-network-continuity.md): automatic retry and verification when Android reports network return, and retained conversation/draft/partial reply. Notification destinations survive failed opening attempts, with recent cached reading available after restart. This improves reconnection and reading; it does not add a server push sender or guarantee replay of missed completion events.

## Android implementation

`BackgroundMonitoringService` uses the `specialUse` foreground-service type with a manifest description of continuous self-hosted chat monitoring. `MonitoringRuntime` retains the app engine across activity lifetimes and serializes native start/stop acknowledgements. No second isolate or duplicate session client is created. Any Play distribution must describe this foreground-service use case in its declaration.

## Settings and text

On first launch, after the first screen appears, Wing requests Android notification permission through the native dialog if notifications are not already enabled. Acceptance or denial is remembered on this device, so subsequent launches do not ask again. A failed platform request can be retried on the next launch. No test alert is posted during startup.

App settings has independent completion/attention switches, **Show message previews** (on by default), and a permission/test action. Each alert shows the chat name and connection/profile. Replies and stopped work use expandable text. Approvals use a decorated native layout with every backend-supported choice: Once, Session, Always…, and Deny. At large text sizes the choices use two rows. Side and background answers use their own reply text. Status-only transitions say Chat updated without claiming a successful result. Turning previews off leaves the chat name and short status. Tapping opens the owning chat. The built-in test proves OS posting, not coverage of actual server work.

Reply previews omit reasoning, code blocks, tool output and URLs. Approval previews show the command being authorized. Secure-input requests and failures use fixed text. Alerts use private lock-screen visibility; Android settings control exposure or generic system text. See [Privacy](../PRIVACY.md). Each scoped chat has one notification slot. Unresolved input takes priority over the latest unread result. Mixed input requests preserve first-seen FIFO order and show counts; accepted or remotely resolved requests advance to the next request. The same dismissed state stays dismissed across refreshes and restarts.

All approval actions require unlocking. Sending keeps the alert visible with disabled choices until Hermes confirms acceptance; failure retains the request. Permanent approval always opens a matching-pattern confirmation in the chat. A command too long to review in the notification also opens the chat before confirmation. Hidden previews provide Review only.

While the existing watcher runs, a single 30-second timer reconciles pending notices against corroborated runtime/open-request snapshots and the approval queue. Resume also reconciles once. Pending requests never extend the watcher's lifetime. Stock desktop read watermarks do not prove the latest answer was visible, so desktop opening does not clear result notifications; completed desktop decisions can clear pending-input notices.

## Event coverage

Loaded chats receive session events through their attached transport. The server's global `sessions.changed` broadcast is an empty, coalesced invalidation. Android uses it to reconcile status snapshots for connected targets; it does not treat it as a completion payload or attach every historical chat.

After an idle connection reconnects from the chat list, a previously loaded chat
may no longer have a session event subscription. If the global snapshot reports
that chat working or starting while Wing considers it nonbusy, Wing reattaches
that chat with stock `session.resume` and `omit_messages=true`. This restores the
watcher and subsequent answer events without reopening its transcript, fetching
history, resuming every idle chat, or adding background polling. A live event that
overtakes the reattach response takes precedence over that older response.

Establish a silent initial baseline, retain verified profile ownership and reconcile meaningful running/waiting/completed transitions. Unknown, disconnected or failed reads must not become completion alerts. Rapid turns can occur between snapshots, an idle transition can be missing, and a failed read can leave a gap. See [issue #9](https://github.com/tarkilhk/Wing/issues/9).

Unopened child-only work also depends on the global backend contract described in [HUP-003](UPSTREAM_HERMES_BUGS.md#hup-003-global-activity-omits-child-only-work). Adding switches or passing a test notification does not close that gap.

## Tap routing

Each notification retains connection/profile/durable-chat identity and request/task or result revision. Stable IDs avoid unrelated replacement, startup navigation retries when initialization is incomplete, and stale connection credentials invalidate obsolete targets. A tap for the same open chat reuses its view; when several requests race, the newest tap wins.

Routing checks include two different chats in the same profile and tapping an
older alert after a newer alert has been posted. A system-generated group header
is not an individual chat target.

Reading the latest answer in Wing clears that result's notification. Opening older history or reaching only newer tool activity does not. For main answers without a stable Hermes message ID, tapping deliberately opens the latest available assistant reply (the user-approved option 2); history may have advanced since posting. No copied answer or prose matching is used.

Refresh server state when opening the chat. Notifications supplement that state and are not the durable record of a result or pending request. The unsent queue still needs a running, connected client to drain.

## Verification

Production-controller live-event tests, native permission/posting/tap tests and fixture reconciliation tests cover different boundaries. The emulator lifecycle fixture checks posting after Home, activity destruction/recreation, and forced Doze with the battery exemption, plus idle startup, multiple simultaneous chats, notification retention after the last chat asks for input, reply/resume, and wake-lock release when work ends. These checks do not guarantee every manufacturer policy or every server event. Use the relevant drivers listed in [Testing](TESTING.md) when notification behavior changes.

### Native lifecycle regression

Build and install the isolated fixture (never over a production app):

```sh
flutter build apk --debug --target-platform android-x64 -t integration_test/background_monitoring_device.dart
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
python3 tools/qa/check_background_monitoring.py --serial emulator-5554
```

The driver rejects physical devices and restores its power-test settings. It uses production controllers and Android posting with deterministic gateway fixtures, without model calls. Host tests cover registration-free startup, permission/category changes, battery status, start/stop races and event deduplication.

### Revamp verification

`integration_test/notification_revamp_device.dart` exercises production WingApp,
controllers, native rendering, approval routing, and visibility handling against
a fake Hermes transport. Build with `ORG_GRADLE_PROJECT_notificationQa=true`
and `-t integration_test/notification_revamp_device.dart`; this uses the isolated
`com.tarkilhk.wing.notificationqa` package. Its loopback control endpoint is port
18766. Never use this test entry point for a distributed build.

The coordinator, answer-visibility, approval-queue, startup-permission and
monitoring tests cover replacement, FIFO, restart/dismissal, accepted responses,
stale targets, preview privacy, and failure retention.
