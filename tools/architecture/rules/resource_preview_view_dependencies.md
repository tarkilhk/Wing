# Resource preview dependencies

ARCH_RESOURCE_PREVIEW_VIEW_DEPENDENCIES checks four canonical preview/image
view libraries and their actual parts. They cannot expose byte codecs, transport
error interpretation or file delivery adapters, including export barrels. Typed
resource-reader imports and native reader factory composition remain supported.

Run `dart run tools/architecture/rules/resource_preview_view_dependencies.dart`.
Exit0 means no violation,1 means a violation,2 means unsupported/invalid input.
Six finite fixtures run in resource_preview_view_dependencies_test.dart, including
missing canonical view input. PR/release quality gates require production scans.

This namespace guard does not prove native lifetime, allocation budgets, arbitrary
Dart-core address policy or cancellation. Existing owner/resource/native controls
and exact retired identities cover their actual observable regressions.
