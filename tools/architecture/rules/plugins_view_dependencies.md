# ARCH_PLUGINS_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_plugins_page.dart` library
and its actual parts must not import or export a namespace exposing the canonical
`lib/core/services/administration_repository.dart` or
`lib/core/services/profile_gateway.dart` library. The former view directly held
`ProfileAdministration`, called plugins RPC, decoded mutable rows, and owned
toggle/readback policy. `ProfilePluginsSession` now owns that workflow; the view
renders immutable observations and forwards refresh/toggle intent.

This independently executable rule configures the unchanged
`tools/architecture/view_adapter_dependencies.dart` helper with the actual
`AdminPluginsPage` marker and these two library paths. Direct imports/exports,
local export closure, normalized relative/package URIs, conditional alternatives
and actual parts are included. Prefixes and `show`/`hide` do not excuse a declared
dependency. Typed owners importing raw adapters internally are valid: ordinary
transitive imports are not followed. Unrelated same-named libraries/types remain
valid. The actual Administration factory composition remains outside this
completed view library; there is no wholesale feature exemption.

Findings exit 1; valid input exits 0. Missing/ambiguous view marker, library roles,
actual parts or visible authored namespaces fail INPUT with exit 2. This is the
existing helper's declared namespace property; it does not resolve symbol use or
prove that every business decision has left the UI.

```sh
dart run tools/architecture/rules/plugins_view_dependencies.dart --json
dart run tools/architecture/tests/plugins_view_dependencies_test.dart
```

Six focused detector fixtures cover original direct administration import,
exported gateway namespace, actual part, typed owner/model and separate legitimate
composition, unrelated homonyms, and missing-part input. Exactly three actual
source CLI representatives assert exits 1/0/2 plus diagnostic identity/location
or INPUT output. Wider namespace robustness is retained by the existing shared
helper's accepted capabilities fixtures; no new resolver or repeated request
matrix is added. Root owns original/current production CLI proof, CI wiring,
feedback acceptance and focused execution; this author handoff runs no jobs.

The actual original source import was line 2,
`../../services/administration_repository.dart`; it must produce
`ARCH_PLUGINS_VIEW_DEPENDENCIES` at that path/line. The successor typed view must
produce no finding. Captured profile/lifetime, physical RPC dispatch, immutable
alias isolation, malformed observations, positive ACK/readback and unknown-effect
no-replay remain behavioral properties in `test/profile_plugins_session_test.dart`.
Computed/dynamic dataflow or renamed canonical adapter paths are outside this
finite contract and require an explicit rule update when the architecture changes.
