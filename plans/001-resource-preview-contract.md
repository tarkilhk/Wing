# Captured resource preview ownership

HtmlPreviewReader owns original source, decoding/render budget, retry, error and
share state. PdfPreviewReader owns captured download, native document, page and
copied readonly page-image observations. Its native document stays leased while
an admitted page render settles; retirement suppresses late publication and
closes late or held native resources exactly once. It releases original bytes
after native open. ImageResource owns embedded/address decoding and byte bounds
for inline and attached images. Product views retain layout, ImageProviders,
visibility mounts and native reader factory composition.

OwnedRemoteFiles borrows captured transport and releases its admitted operation
lease in its own application library. RemoteFileSaver releases undispatched
staging failures. On Android the pinned share adapter copies bytes into its own
provider cache before completing, permitting Wing staging release; other real
platform recipient lifetimes retain their existing admitted staging behavior.

The small resource_preview_view_dependencies command prevents codec/raw delivery
namespaces in four canonical views, including parts and export barrels. Exact
retirement protects18 removed declarations. Existing focused controls cover
immutable bytes, retained original HTML source, bounds, retries, native held
decode and staging failure. Original PDF/staging implementations fail those last
two controls. Final native/device/performance and rendered acceptance remain open.
