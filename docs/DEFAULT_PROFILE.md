# Desktop default profile: backend availability

Verified on 2026-09-26 against upstream `NousResearch/hermes-agent` main commit
[`11e22f25823cdb0bec7d86e8591f6415eb0b58e6`](https://github.com/NousResearch/hermes-agent/commit/11e22f25823cdb0bec7d86e8591f6415eb0b58e6).

**The desktop app's “Set as default” selection is not exposed by the stock Hermes
backend.** It is a preference saved by Electron on the desktop machine. Wing
cannot discover that selection by querying its Hermes server.

## Evidence

The profile menu compares the selected route's `connectionId` and `profile` with
the saved default, and calls `setDefaultProfile(route)`. That function calls
`window.hermesDesktop.profile.setDefault`, which is an Electron IPC bridge, not a
Hermes API request.
[Menu](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/src/app/chat/sidebar/profile-launch-menu.tsx#L22-L51),
[renderer store](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/src/store/default-profile.ts#L18-L50),
[IPC bridge](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/electron/preload.ts#L319-L325).

Electron persists `defaultRoute: { connectionId, profile }` in
`app.getPath('userData')/active-profile.json`. Its get/set handlers read and write
that local preference, and changes are broadcast to the desktop's windows. The
same file's `profile` field records last use separately; switching workspaces
does not replace the explicit default.
[File location](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/electron/main.ts#L917),
[persistence](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/electron/desktop-profile.ts#L86-L149),
[handlers](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/electron/main.ts#L16465-L16473),
[window broadcast](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/electron/main.ts#L9038-L9049).

## Similar backend fields mean something different

| Backend information | Actual meaning |
| --- | --- |
| `profiles.list` → `profiles[].is_default` | Identifies the built-in profile named `default`, whose home is the base Hermes directory. Named profiles receive `false`, regardless of the desktop selection. |
| `GET /api/profiles/active` → `active` | Sticky backend/CLI selection written by `hermes profile use`. |
| `GET /api/profiles/active` → `current` | Profile to which the running dashboard is scoped. |

Sources: [RPC profile roster](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/tui_gateway/methods_profiles.py#L266-L285),
[assignment of `is_default`](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/hermes_cli/profiles.py#L994-L1012),
[active-profile REST handlers](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/hermes_cli/web_routers/profiles.py#L777-L804).

The desktop preference's `defaultRoute` and its IPC methods have no matching
backend implementation under `hermes_cli` or `tui_gateway` at the inspected
commit. The conclusion follows from tracing the complete desktop action to
local storage and checking both stock backend surfaces. Existing upstream tests
also explicitly cover the preference surviving restarts and being isolated by
desktop home; tests were inspected, not executed.
[Desktop preference tests](https://github.com/NousResearch/hermes-agent/blob/11e22f25823cdb0bec7d86e8591f6415eb0b58e6/apps/desktop/electron/desktop-profile.test.ts#L113-L168).

A Wing default would therefore need to be a separate client-owned preference
with the current unmodified backend. No application code, backend code, or
deployed state was changed during this verification.

## Wing implementation, 26 September 2026

Chats now renders an outlined home icon for `HermesProfile.isDefault == true`,
using the backend's `is_default` value. Other profiles retain their initials.
The right-aligned profile viewport is capped at five 24 dp targets (120 dp),
with horizontal scrolling to reach additional profiles. Narrow headers can
show fewer at once.

Validation: 36 targeted profile-model, profile-bar and Chats tests passed;
static analysis and diff whitespace checks passed. Rendered the production
Chats screen with eight fixture profiles at 390 dp / 100% text and 320 dp /
200% text in both themes. Inspected the home icon, selected home and scrolled
selection captures under `build/profile-bar-review/`.
