# ARCH_TOOL_SETUP_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_tool_setup_page.dart`
library, including `AdminToolSetupPage`, `AdminToolModelsPage` and actual parts,
must not import or export a namespace exposing either canonical raw adapter:
`lib/core/services/administration_repository.dart` or
`lib/core/services/profile_gateway.dart`. The original setup/model workflow
imported `ProfileAdministration` directly and decoded provider/model/setup wire
policy in the view. The typed `ProfileToolSetupSession` now owns that work.

This command reuses the existing validated capabilities namespace checker in
`tools/architecture/view_adapter_dependencies.dart`. Its graph traversal and
input validation are unchanged; each command supplies its own completed view,
class marker, two adapter identities and diagnostic. It follows local exports
from direct imports/exports, including all conditional alternatives, normalized
relative and `package:wing` paths and actual parts. `show`/`hide`, a prefix or an
unused declaration does not waive the declared dependency. Ordinary imports of
a typed owner that internally imports an adapter remain valid. External
namespaces and homonymous models outside the two canonical paths remain valid.

Missing/ambiguous scope, roles, part ownership or visible authored namespace
input fails closed with exit 2. A violation exits 1; valid input exits 0. The
completed view's `AdminVoicePage` workflow is moved to its own library without a
compatibility re-export; that remaining raw workflow is not claimed as migrated.

```sh
dart run tools/architecture/rules/tool_setup_view_dependencies.dart --json
dart run tools/architecture/tests/tool_setup_view_dependencies_test.dart
```

Eight focused detector cases run in process: original direct repository,
prefixed normalized gateway, conditional export barrel, actual part, typed
owner/model, homonymous model/member, missing part and missing conditional export
although another branch already exposes an adapter. Only direct invalid,
typed-owner valid and missing-part invalid input also invoke the CLI, proving
exits 1/0/2. The unchanged capabilities fixtures retain the shared checker's
broader namespace evidence. No parser/resolver framework, cache, network,
compilation, timing or budget machinery is added.

This guards the declared library boundary, not arbitrary callback behavior,
symbol dataflow or all UI business semantics. A renamed adapter path or alternate
package alias outside the shared snapshot requires a separate explicit contract.
Required production original/successor proof, CI wiring and behavior acceptance
are Root-owned; this source-only handoff claims no executed proof or runtime.
