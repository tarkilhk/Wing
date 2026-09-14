# Diagram previews

Open a completed Mermaid code block with **Open diagram**. The phone creates
one viewer for that diagram, with pinch zoom, light/dark appearance and
**Show source** for selecting or copying the original code. Back returns to
the same chat. Streaming and unfinished blocks retain their source view.

Completed `svg` blocks offer **Open SVG**, and SVG output files
use the same viewer after downloading through their original chat connection.
The source toggle retains the SVG text and copy control. Web SVG links keep
their explicit browser fallback; they are not fetched automatically.

The renderer is the Mermaid 11.16.1 browser bundle, matching the renderer version
in the pinned Desktop audit. Android serves three bundled assets to a dedicated
WebView at a synthetic HTTPS origin. No server connection, authenticated URL,
credential or remote rendering service is involved. The view is disposed on
close; it does not persist conversation state.

Other diagram formats retain
the existing selectable source fallback. Mermaid is limited to 50,000 source
characters and 500 edges. Embedded media, links and custom configuration
directives are disabled. Parse failures show a readable error with source still
available. This is a diagram viewer, separate from the [interactive HTML viewer](OPENING_OUTPUT_FILES.md#html-and-diagram-sandbox).

The native view has no JavaScript interface to app functions. It denies file,
content and network loading, external navigation, windows, downloads and device
permission requests. Only the exact bundled HTML and two JavaScript asset URLs
receive local responses. The shell enforces a content security policy and uses
Mermaid strict mode without binding diagram click handlers.

SVG uses a blob-backed HTML image rather than inserting untrusted SVG elements
into the page. It is limited to 262,144 source characters and an intrinsic width
and height no greater than 8,192 pixels. The shared shell releases object URLs
after loading, errors, replacement or disposal. It does not run SVG scripts or
provide clickable SVG navigation. External resources remain unavailable in this
image context, so self-contained files work best. See the browser restrictions
for [SVG as an image](https://developer.mozilla.org/en-US/docs/Web/SVG/Guides/SVG_as_an_image).

References checked during implementation:

- [Mermaid strict mode](https://mermaid.js.org/config/schema-docs/config-properties-securitylevel.html).
- [Android local web content](https://developer.android.com/develop/ui/views/layout/webapps/load-local-content).
- [Chromium interception order](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/android_webview/browser/network_service/aw_proxying_url_loader_factory.cc#394)
  and [network blocking](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/android_webview/browser/network_service/net_helpers.cc).
  HTTPS requests can receive an intercepted local response while network fallback
  remains blocked. This source check does not replace live device verification.

## Vendored renderer

`android/app/src/main/assets/diagrams/mermaid.min.js` is copied without changes
from `dist/mermaid.min.js` in the npm `mermaid@11.16.1` tarball. It is 3,566,058
bytes before APK compression and has SHA-256
`18327bef70d96fb505fe7287d9f6a7362ebf07ff6576ddfaffb1a06f3e1a2954`.
Its embedded third-party notices are retained. The accompanying Mermaid MIT
license and the license of its bundled DOMPurify 3.4.0 are included in the same
directory. No Flutter dependency was added.

To update the bundle, obtain an explicitly reviewed version with `npm pack`,
copy its standalone browser bundle and licenses, update the hash/version here,
and rerun the browser, Flutter and native build checks. Do not replace the
bundle with a CDN URL.

## Verification after an update

Run `node scripts/test-diagram-preview.mjs` against the actual bundled renderer. Set `CHROME_PATH` for a nonstandard Chrome location. The harness uses development-only Playwright Core; install it with `npm install --prefix build/diagram-vendor --no-save --ignore-scripts playwright-core@1.58.2` or set `PLAYWRIGHT_CORE_PATH` to an existing installation.

Check Mermaid labels/layout in light and dark, rejected links/configuration, parse errors and source fallback. Check SVG script/external-resource blocking, dimensions and object-URL cleanup after success, failure and replacement. Run the affected Flutter tests and native build, then inspect on-device zoom and Back. Host browser fixtures do not establish Android WebView behavior. See [Testing](TESTING.md).
