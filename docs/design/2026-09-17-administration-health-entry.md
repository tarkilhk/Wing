# Hermes health

The owner approved a Server/Profile mock on 18 September 2026, replacing the
previous combined health verdict. The main task is to see what needs attention
and open the relevant result or recovery action. Refresh and Check profile are
explicit controls; connection, runtime identity and observation times are context.

## Composition and alternatives

A combined status banner with expandable healthy checks obscured the source of
unknown coverage and occupied the most prominent space. Separate Server/Profile
tabs reduced the initial list, but hid ownership and added a tap between routine
checks. The selected arrangement keeps two visible groups, stable observation
rows and scoped detail pages. It gives the actual issues the visual emphasis.

Server contains Doctor, security audit and Logs, followed by quiet runtime-profile
metadata. Profile contains a dropdown and Check profile, then Provider access,
Model, Tools, Connectors and Scheduled tasks. Usage follows the profile rows.
The profile selector stacks above its action at narrow widths or enlarged text.
Doctor/audit never run automatically and retain their captured server scope.

The visual language stays within Studio: navy-charcoal canvas `#101B24`, opaque
panel `#192934`, primary text `#EBF1F2`, muted context `#ADBDC4`, teal action
`#65C7BC` and border `#344C58`, with their shared light-theme counterparts.
Use the existing body/title scale, stronger row titles, 16 dp gutters and 8 dp
group corners. Monospace is confined to raw diagnostic/log output. Semantic
warning/error colors identify actual findings; configuration icons remain neutral.

Provider access consolidates configuration and sign-in observations, explicit
checks and recovery into one submenu. Other observation submenus show the actual
result and timestamp with a direct link to the owning editor. Doctor uses parsed
findings and an expandable full-output panel. Other diagnostics display actual
output without interpreting process completion as success. Run again is separate
from reading an existing result and requires a known completed operation.

Logs keeps server-only source/severity/search controls and a bounded, selectable
output panel with an explicit empty state. Usage retains profile/day scope,
sorting, per-model drilldown, estimated cost coverage and unavailable values.
No client or server repair endpoint is invented. See the current
[API and state contract](../ADMINISTRATION.md#health-observations).

## Verification

Use `test/administration_health_entry_test.dart` for direct-entry loading, explicit
checks, canonical profile switching and root/submenu renders. Captures cover
healthy, setup-needed, expired-sign-in and unavailable states in both themes,
412 × 832 dp normally and 320 × 640 dp at 200% text.

Use `test/health_details_design_test.dart` for Usage, Logs and audit at 412 dp and
320 dp/200% in both themes, including expanded/scrolled results. Doctor findings,
failed refresh and raw output are covered by `test/doctor_diagnostic_page_test.dart`.
Navigation regressions also cover captured action identity and server-only requests.

Capture flags are `CAPTURE_ADMIN_HEALTH`, `CAPTURE_HEALTH_DETAILS`, and
`CAPTURE_DOCTOR`. The first two load `/tmp/wing-header-fonts/roboto-regular.ttf`
and `materialicons-regular.otf`; details also load `mono.ttf`. Doctor uses
`CAPTURE_FONT_DIR`. Generated evidence belongs under ignored
`build/administration-health`, `build/health-details` and `build/doctor-preview`.
Inspect the actual images: passing assertions alone do not establish design quality.
These are fixture-backed Flutter renders, not proof of live provider operation.
