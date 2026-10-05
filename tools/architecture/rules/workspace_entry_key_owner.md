# ARCH_WORKSPACE_ENTRY_KEY_OWNER

The canonical remembered-instance key belongs to the existing AppPreferences
containing library and its actual authored parts. This finite rule rejects:

- Capturing `WorkspaceEntryCodec.storageKey` from its canonical model anywhere
  else under `lib/`.
- A call to the pinned SharedPreferences class's keyed read/write API whose first
  argument is exactly `last_connection_id`, as a direct string literal or resolved
  literal-backed const variable/field or simple const alias in authored sources.

The cheap AST prefilter builds a finite name catalog from exact key string const
initializers and their simple identifier/property const-alias closure across
declared sources. Only exact key literals or names in that catalog select keyed
method calls for resolution; canonical `storageKey` captures remain candidates.
Names grant no exemption or violation: resolved declaration identity and exact
const value decide the result. Ordinary variable arguments on common method names
do not select unrelated libraries. Unrelated homonyms may enter the conservative
catalog but cannot produce a finding without canonical API provenance.

The codec's own static const declaration remains permitted. The canonical codec
class/key and AppPreferences class must exist uniquely; missing authority, invalid
actual part ownership or unsupported/unresolved selected provenance fails input.
Library identities come from the existing Snapshot. Existing analyzer elements
establish canonical declaration provenance; the existing semantic-context helper
supplies the package/SDK context. No new namespace resolver or framework is added.
Conditional candidate dependency closures fail input pending explicit branch proof.

Unrelated same-spelling classes/members, normal strings used for display and raw
preference operations for other keys remain valid. Owner-generated typed entry
observations and commands are the intended caller interface. Existing bootstrap,
permission, shared-draft and raw-owner construction obligations stay inventoried;
this rule grants no broad exemption to Home or `main.dart`.

```sh
dart run tools/architecture/rules/workspace_entry_key_owner.dart --json
dart run tools/architecture/tests/workspace_entry_key_owner_test.dart
```

Six meaningful in-process fixtures cover a raw literal outsider, the actual
original Home const read/write pattern, prefixed canonical capture, actual owner
parts with unrelated APIs, missing authority and a literal-backed const alias
across declared sources. Three source CLI representatives
retain exits 1/0/2 and exact id/file/line/subject/count checks. The fixture reuses the
existing preferences guard's public temporary Workspace/package binding helper.
Root owns CI registration, original-source exit-1/current-source exit-0 proof,
runtime measurements and focused execution; authoring launches no SDK jobs.
For predecessor proof, retain the predecessor Home and overlay the current codec
declaration/authority scope: the original had no WorkspaceEntryCodec declaration.
Missing that new scope is input exit 2, not claimed as an exit-1 finding.

This property does not establish physical write ordering, positive ACK versus
durable readback, rollback, retirement, launcher authority or borrowed lifetimes.
Those facts have controlled owner regressions. Computed const expressions beyond
the simple alias catalog, external package const keys, runtime-computed keys, mutable
aliases, indirect callback/Function.apply operations and delegated storage using
unrecognized APIs are outside the finite literal/const operation property. A
captured canonical key is rejected even before such delegation, but arbitrary
dataflow is not inspected. The existing preferences-view rule separately rejects
canonical raw preference operations inside the completed HomeScreenState class;
the exact retirement guard protects its four removed policy declarations.
