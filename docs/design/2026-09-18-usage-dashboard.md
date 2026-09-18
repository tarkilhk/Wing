# Usage dashboard

The owner selected the title-switching design from the LAN prototype and
approved the stock-Hermes implementation with **1D, 7D, 30D, 90D, 365D**.
ALL is removed. The page helps compare token usage and estimated value, then
inspect a date or a model without leaving its captured profile/connection.

## Implemented layout

- Neutral period buttons; token count and estimated value side by side.
- Token-intensity calendar, one square per UTC session-start date. The year
  view pages through 91 dates with arrows; there is no day slider. Following
  phone feedback, cells are fixed at 12dp with 3dp gaps and no date numerals.
  Longer ranges use seven-row Sunday-aligned week columns; 1D and 7D use a
  compact strip. Cells no longer stretch to fill the available width.
- Breakdown immediately below the grid, one animated composition bar. Its
  clickable title switches model/token-type grouping; Tokens/Cost stays at the
  top right and is independent from the trend controls.
- Trend uses filled, stacked daily token areas with a marker for the selected
  date. Its title offers the same grouping switch. Models remain the default
  grouping as requested; unavailable daily dimensions explain the limitation
  and offer a direct action to show the supported token view.
- Tap a model for exact counts, individual background contributions, rates,
  verification date and pricing source. About this usage carries the coverage
  and estimate methodology, keeping ordinary inspection compact.

The screen follows Studio colors, type, corners and spacing. Period selection
uses neutral tint as specifically requested. Segment widths animate over 300ms
with reduced-motion support. Text and controls wrap at enlarged sizes; exact
counts are also in accessibility labels. Dense calendar cells retain date/token
labels, tooltips and native keyboard activation.

## Data and performance

See the [verified stock data contract](../research/2026-09-18-usage-redesign-data-contract.md).
There are two parallel aggregate reads for each uncached period. Day selection,
calendar paging, grouping and measure changes are local. Previously loaded
periods are reused until Refresh or leaving this screen. Scope changes replace
the cache; late responses cannot replace another selected period.

Daily model history and daily API-equivalent pricing are unavailable. A selected
day never displays period model totals as if they belonged to that date. Token
cost composition also remains unavailable when reported provider costs cannot
be split. Unknown estimates are excluded with a partial-coverage explanation.

## Verification

`test/usage_analytics_test.dart` covers rolling UTC dates, missing counters,
auxiliary contributions, mixed providers and independent parallel reads.
`test/administration_usage_test.dart` covers interactions, caching, stale data,
races, errors, pricing links and actual Flutter renders in light/dark themes at
390dp/100% and 320dp/200%. Existing administration and layout checks exercise
navigation and large numbers in the new detail sheet.

Render with:

```sh
flutter test --no-pub test/administration_usage_test.dart \
  --dart-define=CAPTURE_USAGE=true \
  --dart-define=CAPTURE_FONT_DIR=/home/dev/projects/hermes-android/.toolchain/flutter/bin/cache/artifacts/material_fonts
```

Actual renders are written to `build/usage-review/`. The inspected normal,
enlarged-text, calendar, trend and source views use Flutter widgets and real
fonts, not generated artwork. Authenticated analytics latency on the phone has
not been measured.
