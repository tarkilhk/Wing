# App shell delivery

Implementation slice W00, 2026-09-11. The owner requested navigation and cleanup before new roadmap features. The [product plan](PRODUCT_PLAN.md) remains authoritative for later work.

## Navigation

- A shared left drawer exposes Chats and Activity, followed by Connections, App settings and Hermes administration below a divider. There is no bottom tab bar or intermediate More screen.
- Chats retains the current profile selector, projects, search, archived chats, transcript and composer. Opening settings or administration preserves the selected chat and its current unsent draft.
- Activity moves the existing controller-observed activity into a primary destination. It can open a chat in its original profile. It explicitly describes its limited coverage; server-wide activity discovery is still W01 work.
- Connections uses the workspace theme, a simple list and the existing add/edit/test/restore flows. Username and password are visible in the main form; proxy overrides remain expandable. A device with no saved connection can reach setup and app settings.
- App settings exposes existing theme, accent, text-size and notification-permission behavior. Appearance changes update the app shell. Firebase delivery, new notification categories and an update checker are not part of this slice.
- Hermes administration has a read-only entry showing the selected connection/profile and discovered model/provider fields when supplied, plus Refresh and access to Connections. It does not add persona editing, provider administration or backend restart/update controls.

Profile selection remains local to this client's navigation. No navigation action changes a global active profile or writes server configuration.

### Back navigation, updated 2026-09-15

Android Back opens the left menu from every primary destination, including Connections. Back while the menu is open exits the app. Menu destinations do not form a Back history, and Back from Chats never exposes Connections.

Pages, dialogs and sheets opened above a destination retain their normal Back behavior. Each Back dismisses the topmost view until the original destination is reached, then opens the menu. A conversation is above the chat list: Android Back and the toolbar's Back to sessions button both return to that list, preserving the draft. Back from the root list opens the menu, then exits. Project and filtered chat views retain their existing navigation back to Chats, and Back still cancels an active queued-message edit.

### Personal 2.36.7 validation and deployment

Source commit `6b58bfd` was pushed to `origin/main` on 2026-09-15. Full static analysis reported no issues; the full suite passed 1,630 tests with 10 environment-dependent skips. The clean persistent release checkout separately passed all 46 focused navigation, composer, browser and release-identity tests. These cover each menu destination, preserved drafts and two stacked Administration detail pages. Dependency status was checked; available upgrades were deferred to keep this navigation release on its existing dependencies.

The existing personal release script built the signed, non-debuggable ARM64 APK in `C:\Users\rober\Documents\Projects\hermes-android`. Package `com.tarkilhk.hermes.android`, version `2.36.7`, code `22242` and the pinned Personal certificate all verified. The build retained the existing Android shrinking setting and reported the known plugin Kotlin migration warning.

An in-place `adb install -r` succeeded on the owner's Samsung SM-S918B. Installed metadata confirmed the new version/code and unchanged first-install time, `2026-09-06 22:10:26`. Cold launch succeeded. A phone smoke check confirmed Hermes remained foreground after the first Android Back and left the foreground after the second; the app was then reopened successfully. Menu visibility and stacked-page order were verified by widget tests. The APK is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` in the persistent checkout.

## Cleanup boundary

Removed ten unreachable legacy screens: the old chat, session list, Workspace, workspace session list, Spaces, Cron, Files, Memory, Skills and broad Settings screens. Removed eighteen orphaned UI widgets that served those routes, including the old bottom-navigation shell and panes. Removed the unused legacy execution-controller allocation from the application entry point.

Tests dedicated to the removed UI were retired with that UI. Model/contract assertions in mixed test files were retained. Shared service/model code remains available for later selected work; this slice does not rewrite the current profile controller or migrate persisted data.

Removed unused direct dependencies for Riverpod, GoRouter, Cupertino icons, image picker, text-to-speech, JSON code generation and the unused Cinzel font. Current file/share intake and attachment handling remain. The lockfile drops the resulting unused transitive dependencies without upgrading retained packages.

No saved connection, credential, draft, server conversation or user preference was deleted. Earlier research inventories remain dated evidence of the pre-cleanup commit; references to retired files should be read at that baseline.

## Implementation paths

| File | Responsibility |
| --- | --- |
| [App drawer](../lib/core/widgets/app_drawer.dart) | Shared destinations and scoped navigation header |
| [Workspace screen](../lib/core/screens/profile_workspace_screen.dart) | Connected shell, chat preservation, destination and Back handling |
| [Workspace browser](../lib/core/screens/profile_workspace_browser.dart) | Existing profile/project/chat browsing with the drawer |
| [Settings content](../lib/core/screens/app_settings_content.dart) | Existing device preferences |
| [Overview content](../lib/core/screens/workspace_overview_content.dart) | Existing activity and read-only administration entry |
| [App entry point](../lib/main.dart) | Shared appearance, connection setup, notification/share/launcher entry points |
| [Navigation tests](../test/app_shell_navigation_test.dart) | Draft preservation, profile routing, Back behavior and compact layouts |

## Verification and deployment

- Static analysis passes with no issues.
- The final full retained suite passed with 873 tests and four environment-dependent skips, including the new drawer Back regression test.
- The focused navigation, connection, appearance and release checks also passed.
- Narrow phone layouts and double-size text are covered by widget tests. Rendered Chats, drawer, settings and administration screens were visually inspected with authored data at 390 by 844 pixels. Live gateway behavior has not been revalidated in this slice.
- The first debug build encountered a Windows lock in generated resource output. That generated directory was cleared; no source or user data was removed to resolve it.
- The signed ARM64 release built successfully at `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, about 19 MB. The release script verified the pinned personal certificate, non-debuggable package identity `com.tarkilhk.hermes.android`, version `2.1.2`, and ARM64 split code `21452`.
- Installed on the owner's Samsung SM-S918B using wireless ADB and `install -r`, which returned Success. Installed package metadata confirms version `2.1.2`, code `21452`, upgrading Personal from `2.1.1`, code `21442`. No uninstall or data clear was performed. The launch command succeeded and the Hermes process was running afterward.
- Initial wireless connection failures resolved after restarting the idle ADB server outside the restricted environment. The owner's original endpoint was correct.
- Automatic approval review rejected a live phone screenshot because it could export private chat/account content. No phone screen capture was performed. Verification used package/process metadata and the separately rendered fixture screens; no live transcript or backend mutation was exercised.

The earlier research/roadmap documentation was separately committed and pushed to `main` as `acd8c40`. The implementation in this slice is separate from that documentation commit.
