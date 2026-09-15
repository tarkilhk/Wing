# Wing identity

Approved by the owner on 15 September 2026. This is the selected identity within
the [Studio design system](../DESIGN_SYSTEM.md).

![Approved Wing identity board](images/wing-identity-board.png)

## Name and wordmark

- Write **Wing** in prose, app titles, launcher labels, store listings and accessibility labels. Use **Wing Dev** for development builds.
- The drawn wordmark is lowercase **wing**, with rounded letters. Keep all four letters; the w is a letter, not a rotated or crossed wing symbol.
- Above the i, use three solid, curved, pointed feather shapes derived from the original single-wing emblem. One small feather points up-left; two point up-right. The left feather is navy on cream and cream on navy. The two right feathers are mint.
- Use the compact accent proportions in this board. The final refinement requested an approximately 18% reduction from the previous cluster and slightly tighter gaps. The accepted image is the visual reference; that percentage is an editing direction, not a measured vector specification.
- Keep visible gaps between feathers and above the i stem. The word should read before the accent draws attention.

## Supporting artwork

Use the same pointed feather silhouettes in standalone graphic elements and
enlarged decorations. The old round-ended splash/droplet accents are retired.
The graphic-element specimen uses the same one-left, two-right arrangement;
the splash card uses the two mint feathers enlarged. Preserve text clearance.

Keep the selected winking portrait, dark bob, mint headphones and original
single-wing earcup emblem. The normal launcher uses the portrait; notifications
and optional themed icons use the existing single wing. See the
[production asset record](2026-09-14-app-icon.md).

| Brand color | Value |
| --- | --- |
| Navy | `#0C304A` |
| Cream | `#FFF9EB` |
| Mint | `#C6EED5` |

These colors belong to the artwork. Studio screen tokens and user accent
preferences continue to govern controls. Rounded lettering and circular portrait
masks remain part of the identity. The board's “Wink” heading is the original
concept name; the product name is Wing. “Your agent, with you.” is the selected
tagline, and “A familiar face.” is supporting copy.

## Source and implementation boundary

The checked-in [board](images/wing-identity-board.png) is the approved raster
design reference. The [final refinement prompt](2026-09-15-wing-identity-prompt.md)
records its generation direction. Earlier experimental boards are unselected.
The board does not identify a verified font family or provide editable vector
wordmark masters. Preserve its drawn letterforms when preparing future assets;
do not substitute a guessed font. Production screens keep Studio typography.

This change adopts the name and saves the visual framework. It does not insert
the entire board into the app or replace existing launcher artwork. Generated
mockups are not evidence of implemented screens or backend capabilities.

## Application and repository identity

Wing is the independent client. Hermes Agent remains the server product, so
connection, administration and agent-state references use Hermes where they
identify the server. Preserve upstream author attribution.

Use release application ID `com.tarkilhk.wing`, development ID
`com.tarkilhk.wing.dev`, Dart package `wing` and native namespace
`com.tarkilhk.wing`. App classes, theme tokens, native channels, notifications,
secure-storage namespaces, backup formats and build tooling use Wing names.

This is a clean identity change. Android installs Wing under its new application
ID with separate local data. Backup imports accept only the Wing format, and the
turn journal accepts only its current schema. There are no aliases or migration
paths for the previous identity.

The repository is [`tarkilhk/wing`](https://github.com/tarkilhk/wing).
The Git remote, app release/changelog links and documentation point directly to
this repository. Release workflows use the current GitHub repository context.
