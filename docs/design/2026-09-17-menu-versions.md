# Versions in the global menu

The owner's 17 September direction moves version discovery out of Administration.
The task is to see installed Wing and Hermes versions, notice a confirmed upstream
server update, and open the common Versions & updates screen. Opening the menu or page
only reads; the existing server update confirmation remains required.

## Arrangement considered

Two side-by-side tiles:

```text
[Client 1.0.1] [Server 1.2.3 ↻]
```

Two stacked rows, selected:

```text
… primary navigation …

─────────────────────────
phone  Client version
       1.0.1
server Server version   ↻
       1.2.3
```

The stacked rows give the server entry a full-width touch target, preserve room for
versions and text scaling, and use the existing menu rhythm. They sit at the
bottom when space permits; the whole menu scrolls on short screens or enlarged
text. Avoid a fixed footer that would crowd the navigation at 200% text.

## Visual contract

Reuse Studio: Roboto labels and metadata, 16/13 sp hierarchy, 6 dp action corners.
Light: white panel, #1B2D36 text, #586970 metadata, #126D70 accent, #D6E0E1 divider.
Dark: #192934 panel, #EBF1F2 text, #ADBDC4 metadata, #65C7BC accent, #344C58 divider.
Respect the selected accent family. The identifying detail is the small static
circular-arrows icon on the server row. It is not a spinner. Tooltip and semantics
say Update available. The server row has a disclosure arrow when no update is known. The client row has no arrow or tap action. No update-count badge,
extra heading or permanent Up to date message is needed in the menu.

Only the server row opens Versions & updates, with captured server identity and
update controls. The client version is informational;
there are no client update checks or client update controls. Server actions retain their
host-wide confirmation and action tracking. No connection leaves the client version
visible and labels the server row No server selected.

## Data contract verified

Hermes main was rechecked at `36842e639a178741b70c821e0f4cdd129cd0dfe3`.
The existing [update check endpoint](https://github.com/NousResearch/hermes-agent/blob/36842e639a178741b70c821e0f4cdd129cd0dfe3/hermes_cli/web_routers/actions.py#L257-L306)
returns current_version, update_available and can_apply; force=true refreshes the
upstream comparison. Availability and permission to apply remain separate. Some
installation types cannot establish upstream availability through this endpoint;
absence of a badge must not imply that these installations are current.

The client reads only local PackageInfo.version, as App settings does. Android's
architecture-specific build number remains internal. No client network request,
release comparison, update indicator or update action is part of this feature.

Server checks happen when opening the menu/page and on explicit refresh. Failed
checks show unknown availability, not Up to date. Each page captures its connection;
late reads from a previous connection cannot update the current menu.

Administration has Profile and Health tabs. The former Server tab is removed.

A compact Manage profiles action sits beside the Profile selector to preserve access
to create/clone/rename/delete: this checkout had no other profile lifecycle entry.
It does not appear in Health. The former Server-list duplication is removed.
