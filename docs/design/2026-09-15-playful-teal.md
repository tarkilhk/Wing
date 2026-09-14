# Playful teal theme

On 15 September 2026, the owner approved refining the default theme around
Playful and expressed a preference for teal. The shared Studio theme now uses
deep teal controls on a subtly warm light canvas, and soft teal-mint controls
on navy-charcoal dark surfaces. The portrait retains its original artwork.

The [design charter](../DESIGN_SYSTEM.md#light-and-dark-tokens) records the
updated palette and calculated contrast ratios. Both the base app theme and
workspace theme use the same default accent. Settings displays the name Teal;
the stored `mint` value is retained so existing selections carry over. Iris,
Coral and Gold retain their accent colors. Their panels and text use
the new shared neutral palette. Semantic status colors and stable profile
colors are unchanged.

The owner then questioned whether Teal and Glacier were too similar. Glacier
now uses a cooler blue, `#285F9B` in light mode and `#ABC9FF` in dark mode,
to separate it from Teal's greener hue. The renders below precede this final
Glacier refinement; Teal and all neutral colors are unchanged from the renders.

This change updates theme tokens and the accent label. It preserves layout,
navigation, controls, typography and behavior. It does not recolor the mascot.

## Actual Flutter renders

These captures use the existing Studio widget fixtures and sample metadata.
They show the implemented theme, not an installed phone build. The earlier
[portrait placement record](2026-09-15-playful-placements.md) retains the
previous green theme for comparison.

| Screen | Light | Dark |
| --- | --- | --- |
| Conversation | [Render](images/playful-teal-light-conversation.png) | [Render](images/playful-teal-dark-conversation.png) |
| App settings | [Render](images/playful-teal-light-settings.png) | [Render](images/playful-teal-dark-settings.png) |
| First connection | [Render](images/playful-teal-light-first-connection.png) | [Render](images/playful-teal-dark-first-connection.png) |
| Drawer | [Render](images/playful-teal-light-drawer.png) | [Render](images/playful-teal-dark-drawer.png) |

## Validation

All 73 checks passed in `hermes_theme_test.dart`, `studio_layout_test.dart`
and `app_shell_navigation_test.dart`, with `STUDIO_REVIEW=true` to export
renders. Coverage includes all five accent families in both themes, 320 dp
at 200% text, 360 dp and 840 dp layouts, keyboard/composer interactions,
drawer/settings/administration, and preservation of saved Mint selections.
The shared contrast checks require at least 4.5:1 for body text on the canvas,
panel and selected tint, button text on its accent, and accent text on panels.
`flutter analyze --no-pub` reported no issues.

## Personal 2.36.11 release

Source commit `b440afe` was pushed to main for the owner's requested phone
deployment. The release uses `2.36.11+2228`, with effective ARM64 code `22282`.
The clean persistent release checkout contains that commit; unrelated work in
the task checkout is excluded.

The owner requested focused validation for this color change and stopped the
additional full-suite run. The 73 focused checks and rendered review above
remain the completed validation. Static analysis on the committed release
also finished with no issues. The existing dependency lockfile is unchanged
from the earlier same-day dependency review. No network, lifecycle, navigation
or form behavior changed, and live gateway smoke tests were not repeated.

The existing personal release script built a non-debuggable ARM64 APK using
the pinned signing certificate and default settings with Android shrinking
disabled. `adb install -r` succeeded on the owner's Samsung SM-S918B. Android
reports `2.36.11` / `22282`; the original first-install time remains
`2026-09-06 22:10:26`. No uninstall or data-clear operation was used. Cold
launch returned `Status: ok` and opened the Personal main activity in 1,096 ms.

The APK is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` in
`C:\Users\rober\Documents\Projects\hermes-android`. Its SHA-256 is
`3f029a7dcba50e2c90210b48b52092aa786e65c398deddb7c463c7ae2a2907f8`.
No public release, tag or APK publication was created.
