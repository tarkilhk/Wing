# ARCH_OUTPUTS_VIEW_DEPENDENCIES

The completed ChatOutputsScreen library/actual parts cannot expose canonical
profile_gateway, remote_file_saver, android_file_delivery_service,
media_preview_service or web_preview namespaces. ChatOutputsSession captures
history discovery, retry/page/dedup and preview classification/delivery policy.
The screen renders typed facts and controls navigation/theme/interaction state.
Passive RemoteFileDownload/RemoteTextPreview types remain valid rendering inputs.
The existing low-level view guard independently prohibits dart:io/path_provider.

This small independent command reuses the unchanged namespace checker. Direct
imports/exports, local export closure, prefixes/show-hide and actual parts count;
ordinary transitive imports of typed owners do not. Findings exit1, valid exit0,
missing/ambiguous/unsupported namespaces exit2. Six detector cases and three CLI
representatives reuse the accepted shared contract; no new resolver/cache exists.

Run `dart run tools/architecture/rules/outputs_view_dependencies.dart --json`.
Run `flutter test test/outputs_view_dependency_guard_test.dart` for production
and fixture checks. Exact retirement identities additionally protect removed view
fields/classification helpers. These guards cannot detect renamed policy, late
navigation/delivery or arbitrary dataflow. Existing preview, close-during-download,
HTML/PDF/media and retry cases remain behavioral acceptance. Temporary platform
share-file cleanup remains an explicit resource/native obligation.
