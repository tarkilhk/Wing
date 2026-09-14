# Workspace menus, 2.36.15

The owner requested a visual and functional review of the Chats header menu,
and separately requested anchored project/chat/draft menus with one project
ellipsis instead of the compose pencil. These changes ship together.

## Header menu decisions

- Keep Unread only and Include automated chats. Use compact switches so both
  on and off states are visible. Native menu activation applies the filter
  and dismisses the menu. Preserve paging, scope and existing persistence.
- Keep New project in chat views. Keep New chat on the floating button.
- Keep Archived chats as a destination; omit it inside the archive.
- Keep Refresh as an accessible alternative to pulling the list down.
- In All projects, omit chat filters and the duplicate New project action.
  Its existing floating button creates projects. Keep Project actions inside
  a selected project and mutations on their own row menus.

Use Studio panel/border tokens, 8 dp corners, 16 sp text, aligned 20 dp icons,
48 dp minimum targets and compact trailing switches. Separate filters,
creation/navigation and Refresh with thin dividers. The panel opens below
the ellipsis, wraps text and remains scrollable under viewport constraints.
Retain native focus, keyboard activation, dismissal and reduced motion.

## Verification

Source release revision: `466b1ead460d379d59da2b06c2b39afa42fa8224`.
The release includes latest main through the installed 2.36.14 version.

- Analysis with fatal infos: no issues.
- Focused menu/unread/automation/draft regressions: 23 passed.
- Full suite: 1,649 passed, 10 skipped, one stale New chat text/tooltip
  assertion. Corrected that test to inspect the floating button by its key.
  The final home/release/menu rerun passed all 23 tests, including that case.
- Rendered light and dark menus at 320 dp with 100% and 200% text. Checked
  switch semantics, touch activation at the control edge, keyboard project
  actions, disabled opening and view-specific action eligibility.
- Existing row-menu work passed 80 action/browser tests and six rendered
  Studio checks before integration; the combined full suite covers those files.
- Dependency inventory completed. Keep the existing lockfile for this UI
  release; major plugin updates and their Kotlin migration require separate
  validation. No dependencies were upgraded.

Local evidence is in `build/options-review/`, `build/menu-release-tests.log`,
`build/menu-release-final-tests.log`, `build/menu-release-final-focused.log`
and `build/menu-release-outdated.log` in the OneDrive development checkout.
The signed APK uses the persistent checkout outside OneDrive.

## Phone deployment

Built the signed ARM64 Personal release using `scripts/build-personal-release.ps1`.
The script verified the existing Personal signing certificate, package
`com.tarkilhk.hermes.android`, version `2.36.15`, effective code `22322` and
non-debuggable release status. APK SHA-256:
`5D6214740AB3C3FE8FF16F616DC64BEC3085034C310EAD23A592ACFC68680F43`.

Installed with `adb install -r` on the connected Samsung SM-S918B without
uninstalling or clearing data. Package inspection confirmed `2.36.15 / 22322`.
Launching the main activity returned `Status: ok`. This is installation and
launch verification; no live-server writes or message sends were performed.
