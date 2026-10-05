# ARCH_MCP_SETUP_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_mcp_setup_page.dart` library
and its actual parts must not import or export a namespace exposing either
canonical raw adapter: `lib/core/services/administration_repository.dart` or
`lib/core/services/profile_gateway.dart`.
The original MCP setup view imported `ProfileAdministration` and owned raw
input construction, save/readback and uncertain retry state. The captured
`McpSetupSession` now decides those workflows.

This independent command configures the unchanged
`tools/architecture/view_adapter_dependencies.dart` checker with the actual
`AdminMcpSetupPage` marker and canonical library paths. It follows direct
imports/exports and local export closure, conditional alternatives, normalized
relative/package paths and actual parts. A prefix or `show`/`hide` does not waive
the declared dependency. Typed setup/OAuth/connector owners may import adapters
internally; ordinary transitive imports are not traversed. Unrelated homonymous
libraries, members and external namespaces remain valid.

`admin_connector_routes.dart` is legitimate captured-profile composition.
`admin_plugins_page.dart` retains the separate mixed plugin workflow. Neither
belongs to this completed library or receives a blanket feature exemption.
Workspace picker/navigation and read recovery remain legitimate presentation
interfaces; their ordinary imports are not prohibited by this rule.

Missing/ambiguous scope, roles, actual parts or visible authored namespaces fail
with exit 2. Findings exit 1; valid input exits 0.

```sh
dart run tools/architecture/rules/mcp_setup_view_dependencies.dart --json
dart run tools/architecture/tests/mcp_setup_view_dependencies_test.dart
```

Six focused cases cover the original direct repository import, a local barrel
exposing the gateway, an actual part, typed owner/model/OAuth imports with
legitimate companion composition/plugin libraries, unrelated homonyms and
missing-part input. Only original invalid, typed valid and missing-part cases
also run the CLI, proving exits 1/0/2. Accepted capabilities fixtures retain the
shared checker's wider namespace evidence; no new resolver/framework is added.

This guards a declared library boundary, not arbitrary callback execution,
symbol dataflow or all business semantics. Captured A/B routing, child revocation,
physical dispatch admission, stock ACK/readback and OAuth uncertainty need the
retained owner/adapter regressions. Renamed adapter paths or unsupported package
aliases need an explicit contract update. No cache, compilation, timing or
owner-state matrix is added. Production original/successor proof, CI wiring and
focused execution are Root-owned; this source handoff claims no executed proof.
