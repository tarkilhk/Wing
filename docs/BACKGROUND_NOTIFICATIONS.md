# Background notifications

Wing keeps its authenticated Hermes event connections running in an Android foreground service. The ongoing **Monitoring Hermes** notification identifies this automatic monitoring. Firebase and server push registration are not required.

The service retains the same Flutter engine and workspace controllers when the activity is backgrounded or destroyed. Reopening Wing attaches to that engine, preserving event subscriptions and notification tap routing. It monitors connections opened in this app; it does not subscribe to every saved server or fix missing server events.

## Enabling monitoring

1. Connect to Hermes and enable Android notifications using **Enable notifications** (or **Test notification**) in app settings.
2. Monitoring starts automatically while Wing is visible when a saved connection exists and at least one alert category is enabled. There is no separate monitoring toggle; app settings show an action only when notification delivery needs attention.
3. If settings report battery restrictions, choose **Allow background activity** and approve Android's exemption prompt. This allows the authenticated connection and partial wake lock to operate during Doze. A foreground service alone does not exempt networking from Doze.

Monitoring uses additional battery. Its partial wake lock is held only while the service runs and is released when it stops. Disabling both alert categories, removing the last saved connection, or revoking notification permission (reconciled on app resume) stops the service.

Android force-stop, process termination, a reboot, lost connectivity and manufacturer restrictions can still interrupt delivery. Reopen Wing after the process is terminated. The service deliberately does not restart without its live clients or display a monitoring notification for an empty process. Accepted Hermes work continues on the server.

## Android implementation

`BackgroundMonitoringService` uses the `specialUse` foreground-service type with a manifest description of continuous self-hosted chat monitoring. `MonitoringRuntime` retains the app engine across activity lifetimes and serializes native start/stop acknowledgements. No second isolate or duplicate session client is created. Any Play distribution must describe this foreground-service use case in its declaration.

## Settings and text

On first launch, after the first screen appears, Wing requests Android notification permission through the native dialog if notifications are not already enabled. Acceptance or denial is remembered on this device, so subsequent launches do not ask again. A failed platform request can be retried on the next launch. No test alert is posted during startup.

App settings has independent completion/input switches, optional chat titles and a permission/test action, which remains available after the startup request. Titles are off by default. Event messages use Finished working or Needs your attention, with the selected chat title or Tap to open the chat. The built-in test proves OS posting, not coverage of actual server work.

Avoid secrets, prompt contents and tool output in notifications. Follow [Privacy](../PRIVACY.md) for storage and optional title exposure.

## Event coverage

Loaded chats receive session events through their attached transport. The server's global `sessions.changed` broadcast is an empty, coalesced invalidation. Android uses it to reconcile status snapshots for connected targets; it does not treat it as a completion payload or attach every historical chat.

Establish a silent initial baseline, retain verified profile ownership and reconcile meaningful running/waiting/completed transitions. Unknown, disconnected or failed reads must not become completion alerts. Rapid turns can occur between snapshots, an idle transition can be missing, and a failed read can leave a gap. See [issue #23](https://github.com/tarkilhk/wing/issues/23).

Unopened child-only work also depends on the global backend contract described in [HUP-003](UPSTREAM_HERMES_BUGS.md#hup-003-global-activity-omits-child-only-work). Adding switches or passing a test notification does not close that gap.

## Tap routing

Each notification retains connection/profile/durable-chat identity. Stable IDs avoid unrelated replacement, startup navigation retries when initialization is incomplete, and stale connection credentials invalidate obsolete targets. A tap for the same open chat reuses its view; when several requests race, the newest tap wins.

Refresh server state when opening the chat. Notifications supplement that state and are not the durable record of a result or pending request. The unsent queue still needs a running, connected client to drain.

## Verification

Production-controller live-event tests, native permission/posting/tap tests and fixture reconciliation tests cover different boundaries. The emulator lifecycle fixture checks posting after Home, activity destruction/recreation, and forced Doze with the battery exemption, plus automatic restart when alerts are enabled and wake-lock release when both categories are disabled. These checks do not guarantee every manufacturer policy or every server event. Use the relevant drivers listed in [Testing](TESTING.md) when notification behavior changes.

### Native lifecycle regression

Build and install the isolated fixture (never over a production app):

```sh
flutter build apk --debug --target-platform android-x64 -t integration_test/background_monitoring_device.dart
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
python3 tools/qa/check_background_monitoring.py --serial emulator-5554
```

The driver rejects physical devices and restores its power-test settings. It uses production controllers and Android posting with deterministic gateway fixtures, without model calls. Host tests cover registration-free startup, permission/category changes, battery status, start/stop races and event deduplication.
