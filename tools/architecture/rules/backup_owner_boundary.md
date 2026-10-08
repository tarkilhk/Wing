# ARCH_BACKUP_OWNER_BOUNDARY

One finite owner boundary, independently executable:

```sh
dart run tools/architecture/rules/backup_owner_boundary.dart --root .
dart run tools/architecture/tests/backup_owner_boundary_test.dart
```

Scope is the complete `ConfigBackupService` and `ConfigBackupIo` libraries, the HomeScreenState
`_showBackupConfig`/`_showRestoreConfig` methods, and the two shared passphrase
sheet State classes. Main's composition factory and unrelated workflows are not
declared completed views. The inactive Card was removed after its separate
resolved caller/root proof; the remaining shared sheets are live.

Canonical raw SharedPreferences access/types, ConnectionManager.prefs and
saveDevicePreference are forbidden in those scopes. Canonical backup service,
codec, platform-adapter and owner snapshot/restore operations are additionally
forbidden in the selected UI scopes. The service uses AppPreferences' named bulk
API; UI invokes BackupSession and handles typed choices and passive results.
The platform adapter additionally forbids canonical ConnectionManager,
CredentialStore/FlutterSecureCredentialStore, AppPreferences and
ConfigBackupService identity references and their members. Legitimate platform
file reads/writes and UTF-8 decoding remain valid. Selected UI scopes forbid
canonical dart:convert jsonDecode/jsonEncode/JsonCodec references; this is a
finite codec boundary, not a ban on presentation maps or unrelated lookalikes.
Unrelated declarations with the same spelling, presentation maps, labels,
comments and callback invocation remain valid.

Resolved declaration provenance covers imports, prefixes, aliases, barrels,
inherited naked tearoffs and cascades. A parsed candidate filter runs before
creating a semantic context. It always validates the SDK, selected declarations,
selected-file syntax and experiment configuration. Selected-file parts and
conditional imports require explicit branch proof and return input status 2.

The filter proves only direct declaration bindings: an explicitly typed class
field, an explicitly typed top-level constant, or an own class method/constructor.
It follows import/export `show`/`hide` and conservatively unions dependency
conditional exports. A unique direct class declaration with its own unrelated
member can be excluded; interface aliases, inherited members, type parameters, ambiguous
bindings and unknown receivers still require semantic resolution. It does not
infer variable initializers, follow arbitrary return values or exempt a receiver
because of its name. Local, parameter, catch, loop, pattern and generic type
shadows remain candidates. The platform adapter's imported dependency closure
retains candidates for every canonical authority member, including operations
whose spelling is outside the named backup APIs. The application-authority
closure follows package and relative dependencies; SDK libraries cannot own
Wing declarations and are outside this app-authority closure. Storage member
vocabulary and named-type namespace checks still inspect their actual imports.

Storage and JSON candidate names include the actual parsed canonical
SharedPreferences and JsonCodec class members, rather than only a hand-maintained operation list. This preserves
operations such as an imported helper's `createStorage().reload()` even when
its return type is declared outside the selected scope. Bare JsonCodec type
references and imported helper codec accessors also remain candidates. The semantic checker
still decides whether the symbol actually belongs to the forbidden authority.
Unrelated operations remain valid.

Missing selected declarations, unsupported configuration and unresolved
candidate semantic input return 2. A no-candidate result proves this finite
property, and does not replace the mandatory full application analyzer: semantic
errors unrelated to candidates are outside the filter's input-validation claim.
Diagnostics are stable `ARCH_BACKUP_OWNER_BOUNDARY` findings: status 1 means a
violation; status 0 means the selected property passes. The pinned SDK is
validated through the unchanged shared helper. Its private named parameter
experiment is enabled in memory for the analyzer; application options stay intact.

The ordinary host wrapper is `test/backup_owner_boundary_guard_test.dart`; it
runs the production CLI and the independent fixture/CLI proof. All 37 original
fixture payloads remain unchanged, with additional direct-binding, lexical-shadow,
alias, inherited closure, imported factory and storage-helper cases. Source and
freshly compiled CLI proofs cover invalid 1, valid 0, malformed input 2 and an
invalid SDK 2 even for a clean parsed scope. Actual production is checked in both
modes. Prior source/AOT correctness evidence remains separate from this optimized
revision. Both quality workflows require the production command and actual policy
omission tests prove refusal. This revision's quiet feedback-budget acceptance is
pending; functional runs during concurrent work establish no timing budget.

The later complete 1,204-file quiet snapshot accepted a **26-second source
command** and **6-second standalone AOT command** budget for this finite rule
on the recorded host/SDK. This reduces the previously demonstrated semantic
scan cost without changing its original fixtures or swallowing uncertain symbol
bindings. Source timing includes SDK tool startup; the compiled command avoids
repeating compilation. All first/repeated samples returned 0 and the complete
authored hashes remained unchanged. Matching later feedback acceptance must fit
these thresholds; CI timing remains informational. Measurements and binary/input
hashes stay private under
`/tmp/wing-three-optimized-guard-feedback-checkout/build/architecture-program/optimized-feedback/`.
Whole-program ownership and aggregate acceptance remain separate.

This is not a whole-program business-logic proof. Arbitrary helper behavior,
password value flow, resource lifetimes, admission ordering, durable rollback and
partial restoration remain behavior properties. The shared decoder helper may
legitimately trim a URL while the password must remain exact; matching String
normalization symbols cannot establish which value reaches the password through
arbitrary calls and branches. A broad trim ban would reject valid input handling,
and requiring one helper name/direct syntax would lock implementation shape.
The public plain/encrypted exact-password roundtrip regression detects the actual
loss; the owner lifetime/transaction tests cover timing and storage effects.
