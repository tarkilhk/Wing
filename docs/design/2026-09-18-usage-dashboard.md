# Usage dashboard

The owner selected the title-switching design from the LAN prototype and
approved the stock-Hermes implementation with **1D, 7D, 30D, 90D, 365D**.
ALL is removed. The page helps compare token usage and estimated value, then
inspect a date or a model without leaving its captured profile/connection.

## Implemented layout

- Profile-only dropdown in the scope header; neutral period buttons; token
  count and estimated value side by side. Connection selection stays outside Usage.
- Full-year token-intensity calendar, one square per UTC session-start date,
  in one compact Sunday-aligned band of week columns. Smooth horizontal scrolling
  browses the cached year, with the date label tracking the visible weeks during
  dragging and momentum; no day slider or arrow controls. The visible weeks and intensity colours
  remain fixed when changing the range; a contrasting perimeter marks its dates.
  Preserve the possible 366th partial UTC boundary date from Hermes.
- Breakdown immediately below the grid, one animated composition bar. Its
  clickable title, with its toggle icon on the left, switches model/token-type grouping; Tokens/Cost stays at the
  top right and is independent from the trend controls. Both the rows and bar
  segments rank highest to lowest for the selected measure, with unavailable
  values last, deterministic ties and stable category colours.
- Trend uses filled, stacked daily token areas with a marker for the selected
  date. Its title offers the same grouping switch. Breakdown defaults to models and Trend defaults to
  token types following phone feedback; unavailable daily dimensions explain
  the limitation and offer a direct action to show the supported token view.
- One passive row per exact model ID, combining providers and auxiliary
  contributions. Each raw contribution is valued before aggregation, preserving
  provider-specific pricing and partial-cost coverage. Rows have no tap action,
  disclosure arrow or detail sheet. About this usage carries the coverage and
  estimate methodology.

The screen follows Studio colors, type, corners and spacing. Period selection
uses neutral tint as specifically requested. Segment widths animate over 300ms
with reduced-motion support. Text and controls wrap at enlarged sizes; exact
counts are also in accessibility labels. Dense calendar cells retain date/token
labels and native keyboard activation. Tapping a date selects it and shows a
small anchored tooltip with its UTC date and exact token total; another tap
dismisses it. Unknown totals explicitly say unavailable.

## Data and performance

See the [verified stock data contract](../research/2026-09-18-usage-redesign-data-contract.md).
First load uses three parallel aggregate reads: year-wide daily activity plus
selected-period daily and model totals. The year read is cached independently
and shared with the 365D trend. Day selection, grouping and measure changes are
local. Previously loaded periods are reused until Refresh or leaving this
screen. Scope changes replace the cache; late responses cannot replace another
selected period.

Daily model history and daily API-equivalent pricing are unavailable. A selected
day never displays period model totals as if they belonged to that date. Token
cost composition also remains unavailable when reported provider costs cannot
be split. Unknown estimates are excluded with a partial-coverage explanation.

## Verification

`test/usage_analytics_test.dart` covers rolling UTC dates, missing counters,
auxiliary contributions, mixed providers and independent parallel reads.
`test/administration_usage_test.dart` covers interactions, caching, stale data,
races, errors, passive model rows and actual Flutter renders in light/dark themes at
390dp/100% and 320dp/200%. Existing administration and layout checks exercise
navigation and enlarged text. `test/workspace_picker_test.dart` checks that Usage
offers profiles only and reloads under the selected immutable owner.
`test/usage_calendar_test.dart` checks complete date coverage without duplicates
for every weekday alignment, full width, date selection and stable geometry
across range changes. It also checks live date-label updates during drags and
momentum, bounded scrolling in both directions, and tooltip dismissal on scroll.
The scrolled calendar renders were inspected in both themes at normal and 200%
text sizes. `test/usage_selection_color_test.dart` verifies all ten
approved accent/theme colours and contrast for extreme inputs.

Render with:

```sh
flutter test --no-pub test/administration_usage_test.dart \
  --dart-define=CAPTURE_USAGE=true \
  --dart-define=CAPTURE_FONT_DIR=/home/dev/projects/hermes-android/.toolchain/flutter/bin/cache/artifacts/material_fonts
```

Actual renders are written to `build/usage-review/`. The inspected normal,
enlarged-text, calendar, trend and breakdown views use Flutter widgets and real
fonts, not generated artwork. Authenticated analytics latency on the phone has
not been measured.

## Accepted full-year activity refinement

The owner selected the full-colour year grid and accent-derived contrasting
outline from `prototype/usage-full-year` (`27da0d5`). The preserved prototype
is `docs/design/prototypes/usage-accent-gallery-prototype.html` on that branch.
Main contains the native Flutter implementation, not the HTML prototype.

The owner subsequently rejected the two-band layout and selected one compact
band. On 19 September, the owner replaced earlier/later arrows with continuous
horizontal scrolling. The newest weeks open initially; scrolling is bounded by
the cached year and unnecessary when all weeks fit. The date label tracks the
visible columns during scrolling, and scrolling dismisses any open day tooltip.
All dates keep the same year-wide intensity scale. The 1D/7D/30D/90D/365D chips
move the period outline while keeping the current calendar position. The outline crossfades with reduced-motion
support, includes zero-usage dates, and follows the actual date perimeter.
Tap any date, including outside the outlined period, for its year-query token
count and day breakdown. “Selected period” restores the period breakdown.

The outline rotates the active accent's OKLCH hue by 180 degrees, caps chroma
at 0.12, and finds the closest lightness meeting 4.5:1 against the actual canvas.
Gamut mapping reduces chroma; contrast is checked after sRGB byte rounding.
Use a 1.75 dp outline over a 3 dp canvas under-stroke. This keeps activity and
selection visually distinct without a hand-picked colour palette. Source-colour
contrast is not a claim about antialiased pixels or the entire UI's accessibility.

The scope-local reader shares and caches one 365-day daily request. The selected
period's model and daily requests stay independent: a year query's first-day
count cannot substitute for a shorter rolling window's partial first-day count.
First load uses three concurrent aggregate reads; the 365D view reuses the year
read. Refresh retries year and period data, retaining successes on independent
failures. No per-session scraping or backend changes.
