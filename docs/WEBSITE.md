# Wing website

The GitHub Pages landing page lives in `website/`. It is static HTML, CSS and
JavaScript with self-hosted fonts and app captures. It has no runtime packages,
analytics, cookies, backend, or build step. All asset paths are relative so the
same directory works under GitHub Pages' `/Wing/` project path.

The primary visitor path is to understand Wing's Android/Hermes relationship,
inspect the real app's workflows, and download the signed Android APK. The
README gives repository visitors a shorter introduction and documentation links.
The website has short, reader-facing feature and setup guides. Repository user
guides and production source remain authoritative for capabilities and
prerequisites; keep the corresponding website explanations aligned with them.
GitHub links are reserved for downloads, source, complete policies and technical
server instructions.

| Website page | Authoritative feature/setup references |
| --- | --- |
| `workspaces.html` | `FEATURES.md`: profiles, projects, Chats filters and drafts |
| `recents.html` | `FEATURES.md`: recent and ongoing chats, status filters and launcher shortcut |
| `live-work.html` | `FEATURES.md` and `TOOL_ACTIVITY.md`: live activity, steering and tool details |
| `results.html` | `FEATURES.md`, production `ProfileMessage`, `MarkdownMessageContent` and resource viewers |
| `health.html` | `ADMINISTRATION.md`: Host, Server and Profile checks and their limits |
| `administration.html` | `ADMINISTRATION.md` and its ownership handoff: profile settings, skills and access |
| `scheduled-tasks.html` | `ADMINISTRATION.md`: schedules, delivery, pause/run and recent-run history |
| `usage.html` | `ADMINISTRATION.md`: period charts, token usage and cost estimates |
| `get-started.html` | `GETTING_STARTED.md`, `SELF_HOSTING.md`, `KNOWN_LIMITATIONS.md`, `NOTIFICATIONS.md`, `CONFIGURATION_BACKUPS.md` and `PRIVACY.md` |

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
Profiles, projects and Recents lead the feature story immediately afterward,
with a Chats capture below its explanation and a Recents capture below its own.
Result handling shows formatting, code controls, message actions and file actions
with the corresponding production widgets. Health and Administration each have
their own visible screen and reader-facing guide. Analytics has its own homepage
section with the activity grid, model breakdown and token trends.
The workflow explorer stays focused on following work and steering a conversation.
Result handling has its own section. Its appearance controls change the app captures, not the page theme.
Tabs support arrow keys, Home and End. Native disclosures provide answers to
setup questions. Icon actions retain accessible names and tooltips. The page
remains readable without JavaScript, and reduced motion disables the opening
animation. Every screenshot is an enlargement link. The shared native-dialog
viewer animates from the thumbnail and returns to it on an image tap or outside
click. Escape and keyboard openings are immediate; reduced motion removes
movement. It locks background scrolling, contains focus and restores the trigger
without changing the reading position. No separate enlargement icon is shown.
The requirements and provider/server costs remain visible.

Keep descriptions grounded in `FEATURES.md`, the relevant user guide and the
current production source. Do not add comparative rankings, testimonials,
performance figures, guaranteed notification delivery, or server operations
without evidence.

Give each guide one reader task. Recents, scheduled tasks and usage have their
own pages; link to those explanations instead of repeating them in longer guides.
Headings name the feature or action. Keep code controls with code, message actions
with messages, and input attachments with chat composition. Remove slogans,
implementation commentary and captions that repeat the surrounding text.

## Page and section purposes

These are editorial constraints, not visitor-facing labels. A section earns its
place by explaining a specific action or outcome and demonstrating the detail
that makes it easier. Put the relevant screenshot after that explanation, with
further-reading links last. Avoid disconnected screenshots in guide headers.
A screenshot may establish context for several controls on the same screen;
do not repeat it merely to illustrate another sentence.

| Page | Reader question and outcome | Wing detail to demonstrate | Further reading |
| --- | --- | --- | --- |
| Home | Can Wing help me run several pieces of work from my phone? | Cross-profile/project navigation, Recents, inspectable activity, reusable results, settings and analytics | Focused guides and download |
| Profiles and projects | How do I find and organize conversations for different agents and projects? | Combined profile filters, project grouping, pins and retained drafts | Recents; profile settings |
| Recents | Which chats are running or waiting for me, and how do I return to them? | Running/Needs input filters; opening a chat selects its profile; back returns to Recents | Live controls; Chats organization |
| Live work | What is the agent doing, and how can I respond or change direction? | Timeline/Tasks/Agents tabs; requests and results; steering/queueing; editable input | Recents; using results |
| Results | How do I read, reuse or export what the agent produced? | Markdown layout; separate code and message actions; file previews and Android sharing | Tool details; sending attachments |
| Health | Where is my setup having trouble, and what can I check? | Host/Server/Profile scopes, timestamps, diagnostic findings and targeted repair links | Profile settings; connection recovery |
| Administration | How do I change the intended agent's configuration without losing my edits? | Selected profile identity; setting search; model/skill/access controls; confirmed saves | Schedules; usage; Health |
| Scheduled tasks | How do I arrange recurring work and see what a run returned? | Schedule editing, delivery choices, pause/run actions and recent results | Administration; result handling |
| Usage | Which profiles and models account for my activity and tokens? | Daily activity, period/model breakdowns and clearly explained cost estimates | Model/provider settings |
| Get connected | What do I need, how do I connect, and what if a check fails? | Install/Cloud/address choices, connection checks and specific recovery steps | Profiles/projects; Recents |

| Homepage section | One message | Demonstration |
| --- | --- | --- |
| Opening | Wing is the Android client for your Hermes setup | Actual conversation and expanded tool output |
| Profiles/projects and Recents | Manage several conversations without losing drafts or the selected profile | Text followed by Chats; Recents text followed by Recents |
| Follow and steer | Inspect work before deciding whether to correct, queue or stop it | Activity with all three tabs on Timeline; held composer controls |
| Markdown/code/files | Read and reuse the exact part of an answer you need | Formatted reply; code controls; message actions; file actions, each after its own text |
| Health and settings | Inspect a problem and change the correct profile's setup from the phone | Health and Administration after their respective explanations |
| Analytics | See activity and model usage, with cost estimates clearly identified | Production analytics screen; link to the usage guide last |
| Download and connection | Install Wing with the prerequisites understood | Signed download, requirements and questions; connection links last |

For each edit, check that the heading, explanation, screenshot and final link
answer the same question. A feature name alone is insufficient: the explanation
must say what the visitor can do, while the image demonstrates the controls or
readability that support that outcome. Preserve actual capability limits.

## App capture provenance

All visible app images use actual Wing widgets with authored demo data, not an
HTML recreation of the app. Capture provenance is recorded here; visitor-facing
copy explains capabilities rather than capture tooling or fixtures.

| Asset | Source |
| --- | --- |
| `conversation-{dark,light}.png` | Production `ProfileWorkspaceScreen`, public-safe research history and context-usage fixture |
| `activity-{dark,light}.png` | Production `ProfileWorkspaceScreen` with authored saved tool calls, a complete todo snapshot and a delegated-agent result; actual Timeline/Tasks/Agents tabs remain on Timeline with code expanded |
| `code-{dark,light}.png`, `message-actions-{dark,light}.png`, `files-{dark,light}.png` | Focused production `ProfileMessage` captures of a code block, reply actions and output file actions, respectively |
| `steer-{dark,light}.png` | Same screen with a live message-start fixture, a drafted instruction and the actual held composer overlay |
| `chats-{dark,light}.png` | Production chat browser with demo conversations grouped into Launch and Research projects across two profiles |
| `recents-{dark,light}.png` | Production `ProfileWorkspaceScreen` Recents destination, with recent messages, one running chat and one needing input across two profiles |
| `results-{dark,light}.png` | Production `ProfileMessage` with Markdown heading, table, quote, code and an explicit report link; demo callbacks make its supported actions visible without performing I/O |
| `administration-{dark,light}.png` | Production `HermesAdministrationContent`, using the existing administration-design fixture with authored website observations |
| `health-{dark,light}.png` | Same production content's Health destination, with existing stock-shaped host fixture data and authored diagnostic/profile results |
| `health-profile-{dark,light}.png` | Same Health destination scrolled to its profile checks in a shorter viewport |
| `tool-{dark,light}.png` | Production `ProfileToolCall`, an expanded code execution receipt with supplied code and output |
| `agents-{dark,light}.png` | Existing `build/activity-family/agents-{dark,light}-1.png` production-widget captures with demo task and live output |
| `analytics-dark.png` | Existing public `docs/screenshots/analytics-dark.png` demo analytics capture |
| `welcome-light.png` | Existing public `docs/screenshots/welcome-light.png` production welcome capture |
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
both live-work workflows, then all nine guides at the same widths. It also checks
assets, local links and cross-page anchors, keyboard tabs, disclosures, visible
text contrast, 200% text on every page, reduced motion and reading without
JavaScript. It opens every visible screenshot, checks enlargement and complete
viewport fit, closes by image/outside/close-button/Escape, checks keyboard and
reduced-motion behavior, interrupts entry, verifies focus restoration and reading
position, and checks that further reading follows the screenshots. Shared navigation uses real anchors; guide reading has no JavaScript
dependency. No client router or deployment fallback is required.
Screenshots and the verification report go under ignored `build/website-preview/`.
To use locally installed browser executables, pass a fourth argument naming a
JSON file that maps `chromium`, `firefox` and `webkit` to their executable paths.
Keep that machine-specific file outside tracked source. To repeat only affected
engines, append a fifth argument such as `firefox,webkit` after the executable
configuration. The default reviews all three engines.
Inspect those renders before accepting a design; automated checks do not judge
composition or copy quality. Browser engines do not substitute for a physical
Android browser acceptance run.
