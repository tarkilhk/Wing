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
| `workspaces.html` | `FEATURES.md`: profiles, projects and Chats filters |
| `bots.html` | `BOTS.md`: continuing bot chats, appearance, hosted discussions and read-only screen previews |
| `recents.html` | `FEATURES.md`: recent and ongoing chats, status filters, conversation gestures and retained navigation state |
| `live-work.html` | `FEATURES.md` and `TOOL_ACTIVITY.md`: live activity, steering, draft preservation and tool details |
| `results.html` | `FEATURES.md`, production `ProfileMessage`, `MarkdownMessageContent` and resource viewers |
| `health.html` | `ADMINISTRATION.md`: Host, Server and Profile checks, device alert policy, incident details, thresholds and monitoring limits |
| `administration.html` | `ADMINISTRATION.md` and its ownership handoff: profile settings, skills and access |
| `scheduled-tasks.html` | `ADMINISTRATION.md`: schedules, delivery, pause/run and recent-run history |
| `usage.html` | `ADMINISTRATION.md`: period charts, token usage and cost estimates |
| `get-started.html` | `GETTING_STARTED.md`, `SELF_HOSTING.md`, `KNOWN_LIMITATIONS.md`, `NOTIFICATIONS.md`, `CONFIGURATION_BACKUPS.md` and `PRIVACY.md` |

The README gives a short introduction, demonstrates profile switching and
Recents, and sends readers to the website for feature walkthroughs and connection
help. Keep server/proxy instructions, contributor information and complete
policies in the repository. Do not duplicate the website's full guides in the
README.

The published website is at `https://tarkilhk.github.io/Wing/`. README website
links use that address. Local README previews map it to the website's LAN preview;
the README draft remains separate from website deployment.

## Local preview

From the checkout root:

```sh
python3 -m http.server 8785 --bind 127.0.0.1 --directory website
```

Open `http://127.0.0.1:8785/` on the same machine. For a phone on a trusted LAN,
bind to `0.0.0.0` and use that machine's reachable address. Starting this preview
does not publish the website or change GitHub Pages settings.

## Publishing

GitHub Pages publishes the root of the repository's `gh-pages` branch with HTTPS
enforced. That branch is an export of the reviewed `website/` directory, including
`.nojekyll`. GitHub runs its managed Pages build and deployment when that branch
changes. No custom workflow or app build is required.

The authored source lives in `website/` on `main`. Review changes on a feature
branch and merge them before publishing. From a checkout of the reviewed source:

```sh
wing_pages_commit=$(git subtree split --prefix=website --quiet)
git push origin "$wing_pages_commit:refs/heads/gh-pages"
```

The export keeps the website's history and copies only website files into the
publishing branch. Keep capture tools, private review output and the README out
of that branch. Do not force-push over a divergent publishing branch; inspect
its changes first.

After publishing, confirm the managed Pages deployment succeeded and that the
public homepage, guides and assets match the reviewed source. Check navigation
and screenshot viewing at the `/Wing/` project path. The first deployed source
was `0cd9d4f`; its website export was `2928a765`. Deployment receipts and browser
captures live under ignored `build/` directories. See
[GitHub's publishing instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

## Design and copy

The website preserves [Wing's approved identity](design/2026-09-15-wing-identity.md):
navy, cream and mint, the portrait, and the selected tagline. `wordmark.svg`
transcribes the current production `WingWordmark` paths, rather than substituting
a font. Manrope supplies display text and Source Sans 3 supplies body text.
The Latin font subsets and their OFL notices are checked in.

The opening pairs a conversation with the expanded tool details behind it.
Profiles, projects and Recents lead the feature story immediately afterward,
with the open cross-profile Project selector below the switching explanation and
a Recents card-stack capture below its switching explanation. The profiles guide
demonstrates the profile switcher, project choices and view controls in their own
sections. Get connected introduces the screen navigator after the first-chat
steps; Live work explains draft preservation beside message composition.
Result handling shows formatting, code controls, message actions and file actions
with the corresponding production widgets. Health and Administration each have
their own visible screen and reader-facing guide. Analytics has its own homepage
section with the activity grid, model breakdown and token trends.
The homepage shows the cross-connection Bots roster and appearance editor;
hosted discussions are explained in the Bots guide. Health
includes alerts: its overview shows Alert settings, and its guide demonstrates
host, backend and profile alert controls and notification details in three short sections. Monitoring limits stay beside the alert settings.
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

Write for a stranger deciding whether Wing fits their work, not for someone
who already knows its controls. The homepage shows the workflows worth trying;
each guide demonstrates one of them. A sentence earns its place by explaining a
useful action, the care that makes it easier, or a condition that affects the
reader's decision. A feature list, repeated heading or vague promise does not.
Show polish through specific behavior: retained drafts, remembered views,
inspectable work, confirmed saves and readable results. Do not describe Wing as
polished instead of demonstrating those details.

These are editorial constraints, not visitor-facing labels. A section earns its
place by explaining a specific action or outcome and demonstrating the detail
that makes it easier. Put the relevant screenshot after that explanation, with
further-reading links last when they earn a place. Avoid disconnected screenshots
in guide headers.
Paired homepage stories share content, screenshot and link rows so their images
line up when displayed side by side. The rows size to the actual text; do not
set fixed heights or add filler to equalize copy. Single-column layouts retain
each story's text, screenshot and link order.
A screenshot may establish context for several controls on the same screen;
do not repeat it merely to illustrate another sentence.

| Page | Reader question and outcome | Wing detail to demonstrate | Further reading |
| --- | --- | --- | --- |
| Home | Can Wing help me run several pieces of work from my phone? | Cross-profile/project navigation, Recents, inspectable activity, reusable results, settings and analytics | Focused guides and download |
| Profiles and projects | How do I switch agents and projects and keep the chat view I prefer? | One-tap profile choices, combined profile/project filters, remembered Group by/Sort by/Show details | Recents; profile settings |
| Recents | How do I find ongoing work and move among conversations? | Running/Needs input filters; two-finger switching; persistent card stack; edge cues and restored filter | Live controls; Chats organization |
| Bots | How do I keep agents for different work and bring them into a shared discussion? | Continuing chats across saved connections; names, appearance and profile settings; hosted discussions with mentions | Profile settings; Recents |
| Live work | What is the agent doing, and how can I respond or change direction? | Timeline/Tasks/Agents tabs; requests and results; steering/queueing; forking at a saved answer; editable input and retained drafts | Recents; using results |
| Results | How do I read, reuse or export what the agent produced? | Markdown layout; separate code and message actions; file previews and Android sharing | Tool details; sending attachments |
| Health | Where is my setup having trouble, what can I check, and when will Wing alert me? | Host/Server/Profile checks; issue bell and triggering readings; warning/recovery thresholds; active-use monitoring limits | Profile settings; connection recovery |
| Administration | How do I change the intended agent's configuration without losing my edits? | Selected profile identity; setting search; model/skill/access controls; confirmed saves | Schedules; usage; Health |
| Scheduled tasks | How do I arrange recurring work and see what a run returned? | Schedule editing, delivery choices, pause/run actions and recent results | Administration; result handling |
| Usage | Which profiles and models account for my activity and tokens? | Daily activity, period/model breakdowns and clearly explained cost estimates | Model/provider settings |
| Get connected | What do I need, how do I connect and find my way around, and what if a check fails? | Install/Cloud/address choices, connection checks, screen navigator and specific recovery steps | Profiles/projects; Recents |

| Homepage section | One message | Demonstration |
| --- | --- | --- |
| Opening | Wing is the Android client for your Hermes setup | Actual conversation and expanded tool output |
| Profiles/projects and Recents | Switch profiles and projects, keep the preferred view and move between ongoing conversations | Switching text followed by the cross-profile Project selector; Recents text followed by its card stack |
| Bots | Find agents across connections, return to their conversations and tell them apart | Roster with pins and work status; appearance editor. Hermes discussion mechanics stay in the guide. |
| Follow and steer | Inspect work before deciding whether to correct, queue or stop it | Activity with all three tabs on Timeline; held composer controls |
| Markdown/code/files | Read and reuse the exact part of an answer you need | Formatted reply; code controls; message actions; file actions, each after its own text |
| Health | Check the host, backend and profiles, then set alerts and inspect notifications | Aligned Health overview and notification screenshots, with the active-monitoring limit and guide link last |
| Administration | Change the selected profile's setup from the phone | Settings overview after the explanation, with its guide link last |
| Analytics | See activity and model usage, with cost estimates clearly identified | Production analytics screen; link to the usage guide last |
| Download and connection | Install Wing with the prerequisites understood | Signed download, requirements and questions; connection links last |

Further reading is optional. A body link must provide additional detail or a
concrete next action. Do not link to the immediately following section, add a
link merely to fill the bottom of a layout, or repeat the same destination in
adjacent sections. Header navigation and a guide's table of contents serve
orientation and skipping; they do not justify duplicate body calls to action.
Labels must describe the destination: a connection guide is not a guide index.

Section headings stand alone. Do not add a parallel summary beside a heading
when the feature explanations below already convey that information. Guide
headers go directly from the title to the contents and the instructions; they
do not preview the same contents in a paragraph. Keep a sentence only when it
adds a capability, interaction detail, prerequisite or limit the reader needs.
Move unique facts out of a redundant summary before deleting it. Empty space
is preferable to text added to balance a layout.

For each edit, check that the heading, explanation, screenshot and any final link
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
| `profiles-{dark,light}.png`, `projects-{dark,light}.png`, `workspace-view-{dark,light}.png` | Production `ProfileWorkspaceScreen` with a focused public-safe project fixture; actual one-tap profile selection, Profile/Project anchored menus and Chat list options |
| `navigator-{dark,light}.png` | Production `AppDrawer` in a minimal Scaffold host; actual destination controls and connection identity, with a no-I/O versions controller showing unavailable version |
| `recents-stack-dark.png` | Production `ProfileWorkspaceScreen` with the website conversation fixture and `ChatNoticeActivityScope`; an inward pinch opens the persistent card stack |
| `bots-dark.png`, `bot-appearance-dark.png`, `bot-discussion-dark.png` | Production `BotsContent` and its routed appearance/discussion screens, with five authored bot profiles, stock-shaped roster status and a public-safe discussion log |
| `health-alerts-light.png`, `alert-settings-light.png`, `alert-thresholds-light.png` | Production Health content, app bar, alert dialog and settings editor composed through `HealthAlertsScope`; existing resource fixture with a consistent 97.3% memory sample and native critical pressure; full Alert settings shows host, server and profile controls |
| `recents-{dark,light}.png` | Production `ProfileWorkspaceScreen` Recents destination, with recent messages, one running chat and one needing input across two profiles |
| `results-{dark,light}.png` | Production `ProfileMessage` with Markdown heading, table, quote, code and an explicit report link; demo callbacks make its supported actions visible without performing I/O |
| `administration-{dark,light}.png` | Production `HermesAdministrationContent`, using the existing administration-design fixture with authored website observations |
| `health-{dark,light}.png` | Production Health destination and `WingAppBar` inside `HealthAlertsScope`, showing Alert settings with stock-shaped host data and authored diagnostic/profile results |
| `health-profile-{dark,light}.png` | Same Health destination scrolled to its profile checks in a shorter viewport |
| `tool-{dark,light}.png` | Production `ProfileToolCall`, an expanded code execution receipt with supplied code and output |
| `agents-{dark,light}.png` | Existing `build/activity-family/agents-{dark,light}-1.png` production-widget captures with demo task and live output |
| `analytics-dark.png` | Production `AnalyticsPage`, with a deterministic 365-day demo history and 30D selected; period totals and model breakdowns use the same daily records. Also copied to `docs/screenshots/analytics-dark.png` for repository guides. |
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

To regenerate the new feature images only, use
`--name 'export bots and a group discussion|export Recents conversation switching|health overview with alert settings|export health alerts and resource thresholds'`.
These opt-in exports use production widgets and do not connect to Hermes. Recents
opens the stack with a two-contact inward pinch, using the application activity scope and
bounded pumping while cached-image futures complete. Health disposes its watcher
after unmounting the capture.

To regenerate only Analytics, add
`--plain-name 'export analytics with 30 days selected'`. Its sample history ends
on 9 October 2026 and uses a fixed random seed so captures remain repeatable.
Copy the exported `analytics-dark.png` to `docs/screenshots/analytics-dark.png`
after reviewing it; the website and README use the website asset directly.

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
both live-work workflows, then all ten guides at the same widths. It also checks
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
