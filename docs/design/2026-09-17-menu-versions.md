# Global menu: Wing identity and server footer

The owner selected the portrait-led arrangement from the three rendered layouts,
then specified the footer order as connection icon → name → status LED, with
server version → update indicator on the right. The header contains only the
larger portrait and Wing, aligned horizontally.

## Selected design

```text
[96 dp portrait]  Wing

… navigation …

connection-icon  Home server  ●        v1.2.3  ↻
```

The 96 dp portrait adapts to 64 dp at enlarged text, keeping the horizontal
alignment. The owner requested Wing's proper lettering in the menu title: use
the shared `WingWordmark` with its feather accent and the same letter strokes as
the welcome screen. Its preferred width is 144 dp, growing to 176 dp at enlarged
text; scale the artwork proportionally to fit the available horizontal space.
Keep its Wing accessibility label. There is no connection/profile subtitle or
client version in the header. Client version remains in App settings.

The borderless footer sits about 8 dp above the safe area. Its two targets have
minimum 48 dp height, extending upward from the visible content. No footer divider,
pills, background fill or extra heading. The connection uses its saved icon,
13 sp name and the shared live-status LED, in that exact order. The right side
shows the installed server version and the existing conditional update indicator.

Long connection names and unusually long versions ellipsize within their own
side. Tooltips and accessibility labels expose the complete name/version. The
connection name opens the existing connection-details sheet, including the full
name and live status. Server version opens Versions & updates. These remain
separate actions. The shared status owner drives the LED independently of version
reads; successful version loading cannot imply a connected chat channel.

Back from either destination reveals the same open menu. The update screen keeps
its captured connection; its return refreshes the menu's version observations.
No connection shows a quiet disabled No server selected identity and no update
action. The drawer remains scrollable at enlarged text and on short screens.

## Alternatives and decision evidence

The owner rejected the version pills, explored three lower borderless arrangements,
then requested larger Wing branding above one compact server footer. The final
comparison covered left-aligned, centered and portrait-led compositions. The
owner selected the rightmost / portrait-led layout, adding the connection name.
Prototype source is captured on branch `prototype/menu-brand-server` at `6ec9e73`.
The winning arrangement is implemented with the existing shared components;
prototype switchers and fixture values are not shipped.

## Verification

Inspected actual Flutter renders at 390 × 844 in both themes, at 100% and 200%
text size. The capture harness waits for portrait decoding before saving images.
Widget coverage checks the saved icon/name/LED order, separate actions, open-menu
return, long names at 320 dp, minimum touch targets, live status changes independent
of version reads, and isolation between connections.

## Data contract verified

The unchanged server-read contract was verified against upstream Hermes main at
`f5d192611032025d2757b07ad838921872126182`.

- [GET /api/health](https://github.com/NousResearch/hermes-agent/blob/f5d192611032025d2757b07ad838921872126182/hermes_cli/web_routers/status.py#L114-L119)
  returns the running process's version immediately, without an upstream request.
- [GET /api/hermes/update/check](https://github.com/NousResearch/hermes-agent/blob/f5d192611032025d2757b07ad838921872126182/hermes_cli/web_routers/actions.py#L257-L308)
  also reports current_version, but awaits upstream comparison and commit lookup.
  force=true refreshes that comparison. Availability and permission to apply
  remain separate; unsupported comparisons must not imply Up to date.

The disappearing-version regression coupled installed identity to the slower
upstream response and erased both on failure. Read process identity independently
in parallel, with a five-second per-attempt limit and one retry after 300 ms for
transient transport failures. A successful update check also confirms identity.
A late health response cannot overwrite a newer observation. Keep the last known
version within the controller across failures, qualifying it as last known when
neither read confirms it. Failed update checks clear the availability badge and
update eligibility even when identity remains available. Disposed controllers
ignore late responses, and connection changes create independent controllers.

App settings shows the client version from local PackageInfo.version. The menu
contains server identity only. No client network request,
release comparison, update indicator or update action is part of this feature.
Android's architecture-specific build number remains internal.

Manage profiles stays beside the Profile selector. Removing the former Server tab
must not remove the only existing profile CRUD entry point.
