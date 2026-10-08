# ARCH_PROFILE_DISCOVERY_WRITER

A same-profile token refresh used two direct `_discovery = ProfileDiscovery(...)`
writer sites. Even equal profile facts received a new identity, invalidating the
browser's workspace projection and rebuilding its saved chat ListView. The owner
now routes discovery publication through private `_adoptDiscovery`, where it can
retain unchanged immutable observations and publish real metadata changes.

This independent parsed rule follows the actual containing library rooted at
`lib/core/services/profile_workspace_controller.dart`, including its parsed,
reciprocal URI parts. Each part must exist, point back to this containing library,
and have that library as its unique parsed owner. Missing, duplicate, named,
nonreciprocal, nested or orphan parts fail input. The full namespace must contain
one canonical `ProfileWorkspaceController` declaration. The class must have one
nonstatic `_discovery` field. Literal bare or `this._discovery` writes may occur
only inside the nonstatic ordinary `_adoptDiscovery` method. Field initializers,
constructor field initializers and field-formal initialization also count as
physical writes outside that method. Original initialize/switchProfile writers,
newly named writers, setters and static homonyms fail. The rule also scans actual
part extensions and top-level functions. An extension directly on the canonical
class is the canonical receiver; even an extension method named `_adoptDiscovery`
gets no exemption. An explicitly typed canonical parameter or block-local receiver
also identifies a canonical write. Known unrelated classes declaring their own
same-named instance field remain unrelated. Other receiver types, casts, aliases,
import prefixes, inferred bindings or inherited fields fail input when their exact
literal field identity cannot be established. No arbitrary field spelling is
treated as proof of the canonical owner.

The existing cheap lexical helper proves parameter shadows. Direct block locals
are recognized after their declaration and inside nested closures. Competing
bindings that this finite check cannot classify (such as for/catch/pattern names,
or local initialization ambiguity) fail input with exit 2; the rule does not
guess that their spelling is the canonical field. Explicit `this._discovery`
remains the own field even beside a shadowing parameter. For named receivers,
typed parameter/block bindings are recognized. An enclosing type parameter that
shadows the receiver type name fails input. A competing catch, pattern,
for binding or local function name in that member fails input conservatively.
Ordinary SDK analysis
must still reject semantic errors and inherited or aliased receiver misuse.

The property is a sole physical writer location. It does not prove profile value
equality, immutable publication, ordered selection admission, observer routing,
callback timing, or aliases/transitive writers. The actual original and repaired
same-List token case plus real profile metadata-change tests establish behavior;
in particular, transient selection-persistence busy state is a separate browser
projection concern. The rule neither suppresses those facts nor changes tests.

Clean input exits 0; unsafe canonical writes produce
`ARCH_PROFILE_DISCOVERY_WRITER` with physical file/line and canonical field
subject, then exit 1. Unsupported scope/source input exits 2 with `[ARCH_INPUT]`.
There is no baseline exemption. Thirty-three fixtures include the original two
violations, sole new writer, actual reciprocal no-write parts, offending part
extensions and top-level writers, unrelated receiver homonyms, and unsupported
bindings/part graphs. Three actual CLI invocations exercise exits 1/0/2 using
the same SDK executable and package configuration as the fixture process.

```sh
dart run tools/architecture/rules/profile_discovery_writer.dart --json
dart run tools/architecture/tests/profile_discovery_writer_test.dart
flutter test --no-pub test/profile_discovery_writer_guard_test.dart
```

The rule reuses existing Snapshot, Finding, CLI and lexical parameter binding.
