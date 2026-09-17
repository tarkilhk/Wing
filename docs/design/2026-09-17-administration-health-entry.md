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
