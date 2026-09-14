# Documentation cleanup, 2026-09-15

This follows the [public release review](reviews/2026-09-15-public-release-review.md). The owner requested a documentation cleanup and fixes for the credential redirect, queued attachment ownership and missing privacy policy.

## Changes

- Rewrote the README around installation, current controls, screenshots and limitations. Moved its detailed inventory to [Features](FEATURES.md).
- Added [Getting started](GETTING_STARTED.md), [Contributing](../CONTRIBUTING.md), [Known limitations](KNOWN_LIMITATIONS.md), a [privacy policy](../PRIVACY.md) and [Play Data safety inventory](PLAY_DATA_SAFETY.md).
- Corrected store metadata to describe reachable functionality and the need for a separately operated server.
- Replaced stale release instructions with current package/signing/version guidance. Preserved the original guide and inherited F-Droid recipe in [the archive](archive/README.md).
- Repaired historical source links with commit-pinned references and clarified dated notification, administration and recovery records.
- Retained MIT attribution. The initial licensing blocker was unsupported and withdrawn; no upstream withdrawal is established.

## Findings and disposition

| Finding | Current disposition |
| --- | --- |
| R1: Dashboard redirects forward credentials | Fixed in source. Every dashboard HTTP client disables redirects, including ordinary session-token authentication and downloads. |
| B2: Queue takes attachments owned by a pending send | Fixed in source. Queue is unavailable until send acknowledgement, and the controller rejects the same invalid transition. Newer draft text and files remain editable and survive acknowledgement. |
| B1: Process death can restore a submitted draft without uncertainty | Open. Documented the narrow acknowledgement window and checking server history before resending. This pass does not change recovery behavior. |
| R2: Discovery/download requests lack deadlines | Open. Documented; transport cancellation and deadlines need a separate fix. |
| R3: Missing privacy information | Policy bundled and linked from App settings. Public hosting and Play Console declarations remain release work. |
| S2-S4, R4-R5: README, setup, release and store documentation | Updated. Inherited F-Droid recipe archived. |
| S1: Licensing blocker | Withdrawn. MIT identification and attribution retained. |

## Verification

Regression tests reproduce the redirect and attachment bugs before their fixes and pass afterward. The focused transport/queue run passed 35 tests. The bundled policy opens from App settings in light and dark themes at 320 logical pixels and 200% text size, with back navigation and no layout exceptions, in two passing widget tests. The asset is read from the actual test bundle; the widget test uses a synchronous bundle to avoid fake-clock I/O stalls.

Final verification passed: 1,642 tests with 10 opt-in skips, `flutter analyze --no-pub --fatal-infos` with no issues, and all local file/image links and heading anchors across 122 Markdown files. The full suite includes concurrent changes in this shared checkout. These checks do not establish a signed APK/AAB, physical-device acceptance or Play approval. No release was published by this cleanup.

## GitHub tracking

Enabled this fork's issue tracker and created [nine bug issues](BUG_TRACKER.md), #15 through #23. Each report distinguishes local fixes, open app defects and backend dependencies. No duplicate issues were present.
