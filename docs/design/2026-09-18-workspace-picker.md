# Shared connection/profile picker

The owner requested separate header interactions on 18 September 2026. The icon
and status LED open Connection details, including the existing live status and
retry action. The connection/profile text opens an anchored dropdown with saved
connections and the current connection's profiles. Selection uses background tint
and accessible selected state; each header target and menu action is at least
48 dp. The text target retains the compact header typography.

Two arrangements were considered: a single dropdown with Connection and Profile
sections, or a connection submenu followed by profile selection. The single panel
keeps current-server profile changes one tap away and shows both selected values
without adding another header control. Selecting a different connection enters
that connection in the current section; reopening the dropdown shows its profiles.
Use the shared Studio surfaces, border, corners and typography in both themes.

Chats, conversation headers, Activity, Administration, Health and nested
administration pages use the shared behavior. Profile changes from a conversation
enter the selected profile's list, retaining the original draft and running owner.
Connection changes use the retained application controller registry and preserve
the current main destination. Nested editors keep their captured scope: the picker
unwinds to the workspace section before changing selection, respecting existing
pop guards. If a guard intercepts navigation, resolve the edit first and select
again; no delayed selection can unexpectedly retarget a later edit.

## Stock API verification

Inspected upstream main commit `d177b119e9c56c9ddc0b7379ffce52341ec06584` on
18 September 2026, retrieved from GitHub's current main commit API.
[Stock profile routes](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/hermes_cli/web_routers/profiles.py)
expose `GET /api/profiles` (lines 654–666) and `GET /api/profiles/active`
(lines 742–756), including separate active and current identities.
The picker consumes Wing's existing profile discovery and client-scoped
navigation; it never calls `POST /api/profiles/active` or changes server launch
selection. Saved connections remain client-owned. No backend change is required.

## Validation

`test/workspace_picker_test.dart` covers independent targets in the four main
sections, connection replacement through Home, retained section and controller,
profile failure, nested editor guards, selected semantics and outside dismissal.
Existing status/retry, chat project-target, navigation, restore and notification
routing suites cover the affected paths.

Actual widget renders with Roboto and Material icons are under
`build/workspace-picker-review/`: normal 390 dp and 320 dp at 200% text, in light
and dark themes. Reviewed menu anchoring, density, selected surfaces and reachable
options. These use synthetic profile data and are Flutter widget renders, not a
new APK installed on a physical phone. Capture with `CAPTURE_WORKSPACE_PICKER=true`
and `CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`.
