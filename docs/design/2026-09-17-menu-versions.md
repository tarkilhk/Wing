# Versions in the global menu

The owner's revised 17 September direction uses two compact version pills on one
row at the bottom of the global menu. Client identity is passive; the server pill
opens Versions & updates. Administration retains Profile and Health only.

## Arrangements considered

Content-width pills, left aligned:

```text
[phone v1.0.1] [server v1.2.3 ↻]   …
```

Equal-width pills, selected:

```text
[ phone v1.0.1 ] [ server v1.2.3 ↻ ]
```

Equal widths give the server a predictable touch target, hold their positions
while loading, and use one compact footer row. No headings, visible Client/Server
labels, subtitles or disclosure arrows. The icons identify each version; tooltips
and accessibility labels spell out the full identity and any update/stale state.
The client pill has no action. Only confirmed server availability adds the small,
static circular-arrows icon. No client release checks or update controls.

## Visual and navigation contract

Reuse Studio's theme colors and Roboto metadata typography. The owner's pills use
stadium outlines, 8 dp separation, 16 dp icons and minimum 48 dp touch targets.
Keep both pills on one row at enlarged text; unusually long version strings can
ellipsize, with the full value in the tooltip and accessibility label. The entire
menu remains scrollable on short screens and at enlarged text.

Push the update screen over the open drawer, preserving both the underlying page
and the drawer's scroll position. Back reveals that same open menu. Refresh the
menu's version observations on return, including after a server update. The
update screen captures its connection and retains the existing host-wide update
confirmation and action tracking.

## Data contract verified

Latest upstream Hermes main was rechecked at
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

The client uses only local PackageInfo.version. No client network request,
release comparison, update indicator or update action is part of this feature.
Android's architecture-specific build number remains internal.

Manage profiles stays beside the Profile selector. Removing the former Server tab
must not remove the only existing profile CRUD entry point.

## Verification

124 targeted tests pass across drawer navigation, version loading, update safety,
administration navigation, app shell and Studio layout. The version tests cover
slow/failed upstream reads, transient identity retry, retained identity with
cleared eligibility, late observations and connection replacement. Both themes
were rendered and inspected at 390 dp/100% text and 320 dp/200% text using real
Roboto and Material icons. Artifacts are under
`build/administration-preview/{light,dark}-{1.0,2.0}-versions-entry.png`.
