# Wing website

The GitHub Pages landing page lives in `website/`. It is static HTML, CSS and
JavaScript with self-hosted fonts and app captures. It has no runtime packages,
analytics, cookies, backend, or build step. All asset paths are relative so the
same directory works under GitHub Pages' `/Wing/` project path.

The primary visitor path is to understand Wing's Android/Hermes relationship,
inspect the real app's workflows, and download the signed Android APK. The
README gives repository visitors a shorter introduction and documentation links.
User guides remain authoritative for capabilities and prerequisites; the
website links to them rather than maintaining a second documentation site.

## Local preview

From the checkout root:

```sh
python3 -m http.server 8785 --bind 127.0.0.1 --directory website
```

Open `http://127.0.0.1:8785/` on the same machine. For a phone on a trusted LAN,
bind to `0.0.0.0` and use that machine's reachable address. Starting this preview
does not publish the website or change GitHub Pages settings.

The initial design is isolated on `design/wing-landing-page`. Publication is
pending owner review. No deployment workflow or automatic publishing trigger
is included. After approval, configure GitHub Pages to publish exactly the
`website/` directory through a dedicated Pages artifact. Keep capture tools and
private review output outside the published directory. See
[GitHub's publishing instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

## Design and copy

The website preserves [Wing's approved identity](design/2026-09-15-wing-identity.md):
navy, cream and mint, the portrait, and the selected tagline. `wordmark.svg`
transcribes the current production `WingWordmark` paths, rather than substituting
a font. Manrope supplies display text and Source Sans 3 supplies body text.
The Latin font subsets and their OFL notices are checked in.

The opening pairs a conversation with the expanded tool details behind it.
The workflow explorer shows following work, steering a conversation, and reading
the result. Its appearance controls change the app captures, not the page theme.
Tabs support arrow keys, Home and End. Native disclosures provide answers to
setup questions. Icon actions retain accessible names and tooltips. The page
remains readable without JavaScript, and reduced motion disables the opening
animation. The requirements and provider/server costs remain visible.

Keep descriptions grounded in `FEATURES.md`, the relevant user guide and the
current production source. Do not add comparative rankings, testimonials,
performance figures, guaranteed notification delivery, or server operations
without evidence.

## App capture provenance

All visible app images use actual Wing widgets with authored demo data, not an
HTML recreation of the app. The page identifies the demo content.

| Asset | Source |
| --- | --- |
| `conversation-{dark,light}.png` | Production `ProfileWorkspaceScreen`, public-safe research history and context-usage fixture |
| `steer-{dark,light}.png` | Same screen with a live message-start fixture, a drafted instruction and the actual held composer overlay |
| `chats-{dark,light}.png` | Production chat browser with named demo conversations and projects |
| `tool-{dark,light}.png` | Production `ProfileToolCall`, an expanded code execution receipt with supplied code and output |
| `agents-{dark,light}.png` | Existing `build/activity-family/agents-{dark,light}-1.png` production-widget captures with demo task and live output |
| `analytics-dark.png` | Existing public `docs/screenshots/analytics-dark.png` demo analytics capture |
| `wing.png` | Production 192px Android launcher rendition, `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` |

The capture runner is `tools/website/capture_app_test.dart`. It exports only the
site's own demo assets and does not contact a server or device. Supply a directory
containing `studio-roboto.ttf`, `studio-icons.otf`, and `studio-mono.ttf`; the
Wing icon font comes from the checkout. Follow the existing font setup in
`test/studio_layout_test.dart`.

```sh
flutter test --no-pub tools/website/capture_app_test.dart \
  --dart-define=WING_CAPTURE_FONTS=/absolute/path/to/capture-fonts
```

Live status intentionally animates continuously, so the capture runner uses
bounded frame pumping instead of waiting for the whole app to settle.

## Browser review

The development-only review runner reuses Playwright Core from the repository's
diagram harness; it adds no website dependencies. Install that locked harness
and its Chromium, Firefox and WebKit browsers before running:

```sh
node tools/website/review.cjs \
  scripts/diagram-preview/node_modules/playwright-core \
  http://127.0.0.1:8785/ build/website-preview
```

It checks five widths (320, 390, 768, 1024 and 1440), both app appearances and
every workflow. It also checks assets, anchors, keyboard tabs, disclosures,
visible text contrast, 200% text, reduced motion and reading without JavaScript.
Screenshots and the verification report go under ignored `build/website-preview/`.
To use locally installed browser executables, pass a fourth argument naming a
JSON file that maps `chromium`, `firefox` and `webkit` to their executable paths.
Keep that machine-specific file outside tracked source.
Inspect those renders before accepting a design; automated checks do not judge
composition or copy quality. Browser engines do not substitute for a physical
Android browser acceptance run.
