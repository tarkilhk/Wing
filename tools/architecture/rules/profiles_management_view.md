# Completed profiles management view boundary

`ARCH_PROFILES_MANAGEMENT_VIEW` protects the one completed library
`lib/core/screens/administration/admin_profiles_page.dart` and **every actual
part of that library**, including authored parts outside `lib/`.

The finite property is:

- Every `AdminProfilesPage` constructor requires an immutable zero-argument
  `createSession` function returning the canonical `ProfilesManagementSession`.
  Both the function and its returned session must be non-nullable. The view may
  invoke that factory; direct construction and any subclass constructor whose
  semantic super chain creates another session are forbidden (including implicit
  default constructors and inherited forwarding).
- Authored imports expose only the canonical typed session, `admin_widgets.dart`
  and its existing `admin_navigation.dart` presentation export. Barrels are valid
  when their actual visible namespace contains only these origins; `show` and
  `hide` apply to that namespace. Unused exposed policy/transport types still
  violate the boundary.
- Direct Dart imports are limited to `dart:core`, `dart:async`, `dart:math` and
  `dart:ui`. Installed Flutter/sky-engine and the characters/vector_math/meta
  presentation dependencies exported by Flutter are permitted. Authored classes
  with an external package spelling do not receive this exception.
- Canonical Flutter MethodChannel/OptionalMethodChannel/BasicMessageChannel,
  EventChannel, BinaryMessenger and SystemChannels authority references are also
  forbidden, including construction/capture and inherited native-channel owners.
  Clipboard and SystemChrome presentation helpers remain supported.
- Canonical transport, storage, repository and other domain-policy references
  cannot be introduced through an alias, inherited member, tearoff or cascade.
  Passive inferred profiles presentation values may be read; their constructors
  and a separate direct domain import are not part of the view interface.
- The actual `dart:core` `Map<K, dynamic>`, `Map<K, Object>` and
  `Map<K, Object?>` protocol representation cannot be declared, constructed,
  accessed or referenced here, including aliases. Typed presentation maps, such
  as `Map<String, String>` or `Map<String, Widget>`, and unrelated local classes
  called `Map` remain valid.

Dart analyzer elements establish actual containing-library and type identity.
Prefixes, export barrels, import combinators, typedefs, inherited members and
local shadows do not change the property's verdict. Syntax/semantic failures in
selected view units, missing namespaces, malformed ownership and unsupported
conditional authored namespaces are INPUT failures. Conditional namespaces need
an explicit future all-branch proof; this rule does not silently check just the
current branch. Standard SDK analysis remains mandatory for dependencies and the
rest of the codebase.

The rule always resolves the selected library and checks its semantic errors;
there is no parsed clean-result shortcut. To avoid relinking the full dependency
graph on every local process, it uses the installed analyzer 10.1 implementation's
`AnalysisContextCollectionImpl` with its standard `FileByteStore` through the shared
`tools/architecture/semantic_context.dart` setup. The public
collection constructor does not expose a byte-store parameter. This pinned
implementation dependency must be reviewed with any analyzer update.

Generated summary bytes live under `.dart_tool/architecture/profiles-view/`.
The namespace binds checkout path, resolved SDK path/version/library metadata,
package configuration bytes (or its absence) and root analysis-option bytes.
A pure-Dart miniature library with an explicit SDK needs no package configuration;
cache setup does not add a configuration requirement to that supported input. Analyzer's own keys
add its summary-format version, current source contents, language/features,
analysis options and dependency signatures. The rule still reads/resolves current
inputs and recomputes findings; it never stores or trusts a guard verdict.
FileByteStore validates persisted bytes and an unavailable/corrupt record becomes
a cache miss. Every store has an isolate/process-specific temporary suffix, so
concurrent checks do not share a temporary write filename. Removing the generated
cache is safe and makes the next check repopulate it. First-use **empty-cache**
startup and later **warm-cache, new-process** measurements are distinct; a fast
warm process must never be reported as a fast empty-cache startup.

Fixture coverage preserves the prior 59 payloads and adds unrelated semantic
errors plus reused-cache source/API, removed dependency, actual part, export,
package origin, analysis-option and concurrent-call transitions. Existing alias,
namespace, inferred Map, factory, super-chain and native-channel checks remain
semantic checks.

Run independently:

```sh
dart run tools/architecture/rules/profiles_management_view.dart --root .
dart run tools/architecture/tests/profiles_management_view_test.dart
```

The CLI exits 0 when clean, 1 with stable file/line diagnostics on a boundary
violation, and 2 for invalid or unsupported input. `--sdk PATH` provides explicit
validated SDK provenance; the compiled CLI also discovers the checkout's Flutter
SDK through package configuration. Fixtures run real source and fresh compiled
CLI 1/0/2, including invalid SDK2. Ordinary host coverage is
`test/profiles_management_view_guard_test.dart`, which also checks the real view.
Root owns mandatory CI/catalog integration and quiet-host feedback acceptance.
Measure cold startup and the median of three warm runs for source and compiled
commands against the same complete checkout/SDK; keep numeric results and hashes
in private evidence, never in this public document.

This is a finite structural boundary, **not** a proof that arbitrary local
calculations contain no business meaning. Labels, dialog choices, navigation and
presentation callbacks remain supported. It does not establish lease cardinality,
authority after awaits, current-stock ACK meaning, partial read outcomes, pending
delete settlement, default identity protection or absence of automatic resend.
Those behaviors are covered by `profiles_management_session_test.dart`,
`profile_management_view_test.dart` and
`profile_management_owned_transport_test.dart`. Current-stock implementation
sources were verified at c225c4a04e8b517a357804ebb27367b0c961fd0e; the linter
itself is about client ownership, not a substitute for protocol verification.
