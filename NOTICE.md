# Attribution and license

Wing is an independently developed Android companion for Hermes Agent, maintained in [`tarkilhk/Wing`](https://github.com/tarkilhk/Wing). It began with [rusty4444](https://github.com/rusty4444)'s open-source Android client and continues with its own design, features and releases. Wing is not an official Hermes Agent or Nous Research product.

The original Android client identifies its license as MIT. Wing continues under MIT and retains attribution to the original authors. See [LICENSE](LICENSE) for the full license text. Preserve applicable copyright and permission notices when redistributing.

Contributors to the original client include CarlosReyesPena, CristianGCiocoi, AI-Guru, grunjol, louquillio, sternbergm and rusty4444. The [changelog](CHANGELOG.md) and Git history retain their work and attribution.

Vendored diagram assets retain [Mermaid's license](android/app/src/main/assets/diagrams/MERMAID-LICENSE) and [DOMPurify's license](android/app/src/main/assets/diagrams/DOMPURIFY-LICENSE). These apply to their respective components.

The development-only renderer harness uses [Playwright Core](https://github.com/microsoft/playwright/blob/v1.58.2/LICENSE) under Apache-2.0. It and its test browser are not bundled in the Android app.

The vendored Flutter setup action retains [its MIT license](.github/actions/setup-flutter/LICENSE) and upstream copyright notice.

The New chat and Fork icons use Lucide's `square-pen` and `git-fork` from `lucide-static` 0.468.0, under the [ISC license](assets/fonts/LUCIDE-LICENSE). The app includes a two-glyph font subset and the matching New chat Android shortcut vector; see [icon provenance](assets/fonts/README.md).

The website self-hosts Latin subsets of Manrope and Source Sans 3, distributed under the SIL Open Font License 1.1. Their copyright and license notices are retained in [Manrope's OFL notice](website/assets/fonts/MANROPE-OFL.txt) and [Source Sans 3's OFL notice](website/assets/fonts/SOURCE-SANS-3-OFL.txt). These web fonts are not bundled in the Android app.

Syntax highlighting uses [re_highlight](https://pub.dev/packages/re_highlight) 0.0.3, and the read-only source viewport uses [re_editor](https://pub.dev/packages/re_editor) 0.10.0. Both are by Reqable and distributed under the MIT license. Their dependency licenses are retained in Flutter's bundled notices.
