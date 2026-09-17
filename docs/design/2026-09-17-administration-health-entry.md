# Administration Health entry

The owner approved the tab-free Administration proposal on 17 September 2026.
The Profile/Health tab strip is removed. A pharmacy cross beside the single
header Refresh action opens Health as a dedicated screen. Server operations
remain in their existing owning destinations and the global version menu.

## Implemented composition

The root shows connection/profile scope, the shared direct profile selector with
Manage profiles, search, a compact model/reasoning brief and two settings groups.
Profile descriptions appear when present. Search preserves its input and the
previous overview scroll position when returning from an editor or clearing it.
Health remains reachable without a selected profile.

Health shows actionable selected-profile findings first, then runtime identity
and explicitly run diagnostics, followed by observed settings, access checks
and usage. Runtime identity names the actual launch profile and explains when it
differs from the selected profile. Diagnostic observations survive leaving Health
and opening settings; navigation never reruns them. Explicit access-check failures also
contribute to the indicator and remain attached to their canonical profile. An
ordinary overview refresh cannot erase a retained failure.

The cross has a neutral glyph, status-colored border and a 48 dp target. Unknown,
loading and stale observations do not become green. See [Administration](../ADMINISTRATION.md)
for the observed-health contract and pinned vanilla Hermes API verification.

## Visual assessment

Production Flutter widgets were captured at 412 × 832 dp in both themes with
healthy, setup-needed, expired-provider and unavailable observations. Enlarged
captures use 320 × 640 dp at 200% text. The capture harness is in
`test/administration_health_entry_test.dart`; its sample data is confined to tests.
These are fixture-backed widget renders, not observations from a live server.

An independent reviewer compared the images against the approved toolbar
mockups. The review led to placing runtime immediately after profile findings,
compacting unrun diagnostic actions, and naming affected tools/providers. A
second review found no visible layout blockers. Final captures also show the
explicit different-runtime-profile explanation. All enlarged controls grow and
scroll; at enlarged text the root title moves into the scrolling body so the
header actions remain reachable.

Recreate captures with the local Roboto/Material font files used by the harness:

```sh
flutter test --dart-define=CAPTURE_ADMIN_HEALTH=true test/administration_health_entry_test.dart
```

Images are generated under `build/administration-health/`. The disposable Android
journeys reuse the production-widget harness through
`integration_test/administration_health_entry_test.dart`.

## Verification record

Static analysis passes with no issues. The complete widget/unit suite produced
2,086 passes and 12 intentional skips; its four remaining failures referenced the
removed tabs. Those four were updated to exercise Health navigation and passed.
After the explicit-access-check regression and integration of the latest main,
all 61 affected health, shell, navigation and menu tests passed. Both new
access-check regressions verify status and canonical-profile isolation.

On the disposable API 36 Android emulator, all ten root/Health journeys passed in
both themes, including enlarged text, profile selection, search and Back. The four
existing native editor/diagnostic journeys also passed, including keyboard,
conflict/discard, accessibility action and retained operation output. These use
in-memory observations; they do not establish live-provider behavior. No production
server was changed or model request sent.

Four additional dark/light native visual journeys passed using Android's real
viewport and insets at 100% and 200% text. Twelve native-rendered frames were
exported before the disposable app was removed and visually inspected. Widget
captures retain the separate 320 dp narrow-screen coverage.
The independent reviewer inspected all twelve native frames and found no new
visual blockers or inset collisions; the native renders support the earlier
widget-render assessment.
