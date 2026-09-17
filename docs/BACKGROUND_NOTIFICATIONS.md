# Background notifications

Wing keeps its authenticated Hermes event connections running in an Android foreground service while at least one chat is working. The ongoing **Monitoring Hermes** notification identifies this automatic monitoring. Firebase and server push registration are not required.

The permanent connection indicator uses **Hermes' caduceus**; chat completion and
attention alerts use the **wing** icon. Monitoring has its own notification
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

Android force-stop, process termination, a reboot, lost connectivity and manufacturer restrictions can still interrupt delivery. Reopen Wing after the process is terminated. Work started from another client while Wing is idle cannot wake the app; reopening Wing reconnects it. The service deliberately does not restart without its live clients or display a monitoring notification for an empty process. Accepted Hermes work continues on the server.

## Android implementation

`BackgroundMonitoringService` uses the `specialUse` foreground-service type with a manifest description of continuous self-hosted chat monitoring. `MonitoringRuntime` retains the app engine across activity lifetimes and serializes native start/stop acknowledgements. No second isolate or duplicate session client is created. Any Play distribution must describe this foreground-service use case in its declaration.

## Settings and text

On first launch, after the first screen appears, Wing requests Android notification permission through the native dialog if notifications are not already enabled. Acceptance or denial is remembered on this device, so subsequent launches do not ask again. A failed platform request can be retried on the next launch. No test alert is posted during startup.

App settings has independent completion/attention switches, **Show message previews** (on by default), and a permission/test action. Each alert shows the chat name and connection/profile. One expandable text layout covers updates (Reply ready), input requests (Input needed), and stopped work (Failed or Stopped). Side and background answers use their own reply text. Status-only transitions say Chat updated without claiming a successful result. Turning previews off leaves the chat name and short status. Tapping opens the owning chat. The built-in test proves OS posting, not coverage of actual server work.

Previews omit reasoning, code blocks, tool output and URLs. Secure-input requests and failures use fixed text. Alerts use private lock-screen visibility; Android settings control exposure or generic system text. See [Privacy](../PRIVACY.md). Pending-input alerts and result alerts use separate notification identities so a result cannot replace input needed for the same chat.

## Event coverage

Loaded chats receive session events through their attached transport. The server's global `sessions.changed` broadcast is an empty, coalesced invalidation. Android uses it to reconcile status snapshots for connected targets; it does not treat it as a completion payload or attach every historical chat.

Establish a silent initial baseline, retain verified profile ownership and reconcile meaningful running/waiting/completed transitions. Unknown, disconnected or failed reads must not become completion alerts. Rapid turns can occur between snapshots, an idle transition can be missing, and a failed read can leave a gap. See [issue #9](https://github.com/tarkilhk/Wing/issues/9).

Unopened child-only work also depends on the global backend contract described in [HUP-003](UPSTREAM_HERMES_BUGS.md#hup-003-global-activity-omits-child-only-work). Adding switches or passing a test notification does not close that gap.

## Tap routing

Each notification retains connection/profile/durable-chat identity. Stable IDs avoid unrelated replacement, startup navigation retries when initialization is incomplete, and stale connection credentials invalidate obsolete targets. A tap for the same open chat reuses its view; when several requests race, the newest tap wins.

Routing checks include two different chats in the same profile and tapping an
older alert after a newer alert has been posted. A system-generated group header
is not an individual chat target.

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
