# Authored runtime-root and remaining deletion closure

This is a read-only source review of the current application checkout, supplementing
[the dead-code inventory](001-dead-code-inventory.md). It is not a whole-program
liveness proof or deletion approval. Owners were editing during this review;
refresh the exact source/census and resolved caller evidence before removing a
declaration. Source searches below identify leads and positive consumers; absence
of a search result never establishes deadness. No builds, devices or complete
semantic query were run for this review.

## Initial member closures already completed

The obsolete ConfigBackupCard instance workflow and WingApp.setThemeMode have
been removed and are covered by the retirement manifest. The shipping backup
route uses ConfigBackupActions and its typed owner; the settings route uses the
existing preference owner. Public-member/constructor and branch subtraction
across the full final checkout remains a separate pending review.

The backup widget library remains live through ExportPassphraseSheet and
ImportOptionsSheet. ConfigBackupIo/Service/Codec, cryptography and their supported
native/host controls remain real roots. Removing obsolete card orchestration
does not justify deleting those adapters or their dependencies.

## Direct dependencies and resources

The current pubspec declares 25 direct runtime/development packages. Every runtime
package has a concrete authored import consumer; Flutter/integration/test SDK
packages have their framework or test consumers, and `flutter_lints` is included
by `analysis_options.yaml`. No additional direct-package deletion is established.
The prior `highlight` candidate is already absent from both pubspec and lock;
the preserved dependency/asset audit is historical pre-removal evidence.

Examples that must survive the proposed card deletion:

- `cryptography` is imported by the live encrypted backup codec.
- `share_plus` is used by backup delivery and chat output sharing.
- `file_picker`, `path_provider` and `package_info_plus` are used by the active
  backup I/O owner as well as other features.
- `image` is owned by the bounded image codec library and its actual part files;
  the audited exact version and provenance guard are deliberate dependencies.
- `analyzer` and `yaml` are used by executable architecture guards, not app
  rendering. Lack of a production Dart import is not grounds to remove them.

The current explicit Flutter assets are the offline privacy document, pricing
catalogue, portrait icon and WingIcons font. Their actual readers are
`privacy_policy_screen.dart`, `usage_analytics.dart`, `playful_portrait.dart` and
`wing_icons.dart`. The icon generator reads `playful-master.png` and `wing.svg`,
and writes density variants, store artwork and notification/themed vectors.
The font README and Lucide license preserve source/licensing obligations.
The parent `assets/` registration and empty marker are already gone.

Native renderer assets have a concrete allowlist in
`MermaidDiagramView.ASSETS`: `index.html`, `app.js` and `mermaid.min.js`.
The Mermaid/DOMPurify license files are attribution inputs; absence from that
HTTP asset allowlist does not make their legal purpose dead. Manifest, Android
XML references, Kotlin resource IDs and generator inputs retain launcher density
variants, API/night themes, shortcut resources, notification layouts/icons and
provider paths. `ic_stat_connection.xml` remains a source for the documented
notification-board generator despite not being a shipping notification icon.

The Dart package table does not cover all tool dependencies. The renderer test
workspace pins `playwright-core` through its manifest/lock and is invoked by the
composite CI action. The icon generator requires `sharp` supplied locally or via
`NODE_PATH`; the font instructions require FontTools and an external Lucide
source font. The desktop projection audit loads `esbuild`/TypeScript from the
supplied Hermes checkout. Record these supported tool inputs explicitly rather
than describing pubspec as the complete dependency inventory. A runnable,
documented generator prerequisite is distinct from an application dependency.

## Runtime-root inventory corrections

`roots.json.files` covers authored file presence. `ARCH_AUTHORED_CENSUS` explicitly
does not validate executable roots, selectors, dependency consumers or liveness.
A passing census therefore does not close the following root-table work.

1. **Register the new supported share acceptance entry.**
   `integration_test/share_intake_device.dart` has an actual guarded `main`, a
   local-only fixture endpoint, and is used by `check_external_share.py
   --provider-faults` and `native_share/README.md`. Record the Dart entry's
   release exclusion and explicit QA define, together with the native controlled
   camera branch's DEBUG, native-QA and exact-package predicates. These conditions
   are part of its supported test root, not authority to run it in release.
2. **Register the new independent guard and fixture entrypoints.**
   The current root table omits the completed-model, owned-model, settings,
   overview, provider, memory, deleted-draft cleanup and image guard commands,
   along with several actual fixture mains. They are referenced by the quality
   workflows, architecture README, aggregate or mandatory host wrappers.
   Include native share/voice PSI commands, fixture proofs, JVM runners and
   documented opt-in benchmark entrypoints. Their files being in the census
   is not executable-root evidence by itself.
3. **Record discovery as a root with the real pattern.**
   Both workflows discover `scripts/tests` and `tools/qa/test_*.py`; recently added
   offline tests are rooted by those actual commands even without individual
   rows. Record the discovery directory/pattern and its currently discovered
   TestCase files. `run-administration-live.ps1` is also a separate supported
   Windows/disposable-emulator launcher with captured child-process cleanup;
   classify its platform/tool prerequisites explicitly.
4. **Refresh package consumers after migrations.**
   The `http` consumer list still names the deleted domain
   `models/dashboard_oauth_session.dart`, while the refresh owner now imports
   HTTP from `services/dashboard_oauth_session.dart`. Other lists omit new
   guards, native/resource tests and codec parts. Regenerate parsed directive
   consumers, including exports/conditionals/parts, after a coherent freeze;
   retain explicit SDK/lint/plugin/generator evidence beside them.
5. **Reconcile retained decisions with the executable manifest.**
   DC12's four official-source tools and DC13's five iOS framework entries are
   called retained in the deletion inventory/tooling README but still have
   `needs-decision` status in `roots.json`. iOS has genuine `@main`, scene/plist,
   project/asset and XCTest roots; platform removal is not authorized and no
   Android-first deadness inference applies. DC12 needs each tool's exact input
   contract: the regeneration repro hardcodes a Windows installed checkout;
   attachment repro expects `build/official-desktop-qa`; desktop projection takes
   a checkout with its own Node dependencies; batch generation takes a checkout
   and writes an owned synthetic fixture. Record supported invocation and
   whether it is current-contract tooling or a specific historical diagnostic.
   Do not silently claim those stale environmental assumptions are verified
   against latest stock.
6. **Name generated plugin ownership.**
   Android's Flutter plugin loader and iOS's generated registrant are concrete
   build roots. Current generated metadata also links `path_provider_android`
   to `jni`/`jni_flutter` despite the path-provider plugin's `native_build:false`.
   Classify generated registration through its pubspec/Flutter owner; do not
   remove transitive native plugins merely because app Dart imports use the
   facade package. The generated registrants are not handwritten deletion
   candidates.

No physically missing root path was found in the table read for this review.
The gaps above concern current supported entrypoint coverage, stale consumers
and contradictory dispositions rather than permission to remove more files.

## Remaining closure gate

Once current owners stabilize, freeze the authored census/source and run the
corrected constructor/member query for the two proposed closures. The query's
successful exit means inventory completion, not deletion approval. Review its
exact declaring library, occurrence locations, unresolved dynamic candidates,
inheritance and native/tool registrations. Preserve shared active assertions,
remove only the demonstrated exclusive closure, then regenerate role/root/package
inventories and rerun affected behavior plus root's required coherent checks.

Native declarations/resources still require framework-aware closure review:
manifest classes, Activity/service lifecycle, recognizer/player/TTS listeners,
permission results, channel handlers, platform-view factories and resource
lookups can be live without an ordinary authored caller. Existing native
confinement guards establish their named boundary properties, not whole-native
unreachability. Generated/vendor attribution and required platform scaffolding
remain classified roots. Whole-authored completion remains pending until every
candidate has a reviewed final disposition and the inventory contradictions
above are resolved.

## Current accepted-source disposition

The proposed Card/State and WingApp.setThemeMode closures above are historical:
the former canonical declarations are removed and protected by retired.json.
Shared backup-sheet behavior remains live. Their earlier root-bound query and
retirement evidence remain the deletion proof; present source absence is not a
new semantic proof.

All registered root paths exist on the accepted 1,422-path subtraction source.
Share QA, guard/fixture commands and actual test-discovery roots are registered.
The share entry rejects release/absent QA define, while controlled native camera
adds DEBUG/native-QA/exact-package gates. Android plugin loading now has an explicit
root; iOS AppDelegate already names the generated registrant. Four DC12 tools are
supported source-input diagnostics or synthetic fixture generators with explicit
prerequisites; five iOS reference rows retain framework inputs without implying
feature parity. Neither disposition certifies a run on current upstream.

The 25 current direct packages all have application, test, tooling or configuration
consumers. yaml/path are runtime ProfileIdentityRepository dependencies;
flutter_lints is an analyzer configuration input. Consumer headers were refreshed,
including part files; semantic caller proof remains a separate obligation.
DC08 highlight, DC09 fictional recovery ledger and DC11 marker/parent registration
are removed. No further source/asset/direct-package deletion is demonstrated.

The earlier root-table corrections above are therefore historical, not a current
request to rediscover those roots. Final member/native-dynamic/post-integration
orphan evidence and fixed-source acceptance remain as recorded in the canonical
dead-code inventory. No new rule, framework, compatibility or runtime change was
introduced by this metadata reconciliation.
