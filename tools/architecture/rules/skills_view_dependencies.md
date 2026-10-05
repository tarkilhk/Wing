# ARCH_SKILLS_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_skills_page.dart` library
and its actual parts must not import or export a namespace exposing either
canonical raw adapter: `lib/core/services/administration_repository.dart` or
`lib/core/services/profile_gateway.dart`. The original library, detail, editor,
Hub and preview views imported `ProfileAdministration` and interpreted wire
rows, provenance eligibility, endpoints, conflict checks and command outcomes.
`ProfileSkillsSession` now owns those responsibilities.

This independent command configures the unchanged
`tools/architecture/view_adapter_dependencies.dart` checker. It follows direct
imports/exports and local export closure, all conditional alternatives,
normalized relative/package paths and actual parts. A prefix or `show`/`hide`
does not waive the declared dependency. A typed owner that imports an adapter
internally is valid; ordinary transitive imports are not traversed. Unrelated
homonymous libraries, members and external namespaces remain valid.

Missing/ambiguous scope, roles, actual parts or visible authored namespaces fail
with exit 2. Findings exit 1; valid input exits 0. The existing retirement guard
also protects 19 exact removed skills identities in its canonical view library.
Dialog/navigation methods, local search and usage-order preferences remain
legitimate presentation responsibilities.

```sh
dart run tools/architecture/rules/skills_view_dependencies.dart --json
dart run tools/architecture/tests/skills_view_dependencies_test.dart
flutter test test/retired_declarations_guard_test.dart
```

Six focused cases cover the original direct repository dependency, a local
barrel exposing the second adapter, an actual part, a typed owner/model,
unrelated homonyms and missing-part input. Only the original invalid, typed
valid and missing-part cases additionally run the CLI, proving exits 1/0/2.
The accepted capabilities fixtures retain the shared namespace robustness.

This guards a declared library boundary, not arbitrary callbacks, symbol
dataflow or all business semantics. Exact retirement identities cannot detect
renamed policy. Dispatch retirement, admitted leases, ACK/readback uncertainty
and concurrent server writes need the retained skills owner regressions and
stock contract in `plans/001-skills-ownership-contract.md`. A renamed canonical
adapter or unsupported package alias needs an explicit contract update. No
resolver, cache, compilation or timing framework is added. Production proof,
CI integration and focused execution are Root-owned; this source handoff claims
no executed proof.
