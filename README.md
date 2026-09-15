<p align="center">
  <img src="docs/design/images/wing-readme-hero-clean.png" alt="Wing: Your agent, with you | An Android companion for Hermes Agent" width="1000">
</p>

<p align="center">
  <a href="https://github.com/tarkilhk/wing/releases"><strong>Get Wing</strong></a> &nbsp; · &nbsp;
  <a href="docs/GETTING_STARTED.md">Getting started</a> &nbsp; · &nbsp;
  <a href="docs/FEATURES.md">Features</a> &nbsp; · &nbsp;
  <a href="docs/README.md">Documentation</a>
</p>

# Wing

Pick up a conversation, check on running work, or send your agent the next idea. Wing brings your [Hermes Agent](https://github.com/NousResearch/hermes-agent) to your Android phone, with chats, projects and the tools to keep work moving.

Bring your own Hermes server. Wing is an independent client; it does not run a model on your phone or provide a hosted AI service.

<a id="screenshots"></a>

## A familiar face. Your own workspace.

Navy, cream and mint give Wing its identity. Inside, the Studio interface keeps conversations readable, actions within reach, and light and dark themes ready for your preference.

<table>
  <tr>
    <th>Stay with the conversation</th>
    <th>Bring your own agent</th>
  </tr>
  <tr>
    <td align="center"><img src="docs/design/images/playful-live-dark-conversation.png" alt="Dark conversation view with an agent reply, code block, activity disclosure and message composer" width="300"></td>
    <td align="center"><img src="docs/design/images/playful-live-light-first-connection.png" alt="Light connection screen with the Wing portrait and actions to add a connection or restore configuration" width="300"></td>
  </tr>
  <tr>
    <td>Read replies, inspect tool activity, and draft the next message.</td>
    <td>Connect to your Hermes host and open its profiles and conversations.</td>
  </tr>
</table>

Actual app captures from 15 September 2026. These predate the Wing rename and later interface refinements. Accent colors follow the selected theme.

## From an idea to the result

| Keep the thread | Keep work moving |
| --- | --- |
| **Continue a chat.** Streaming replies, model and reasoning choices, and searchable history. | **Follow the work.** Tool activity, subagents, goals, and supported approval or clarification requests. |
| **Find your place.** Projects, pinned chats, unread filters and Activity across profiles. | **Choose the next step.** Save a draft, queue a follow-up, steer a running turn, or stop it. |
| **Send what you have.** Photos, files, dictated drafts and Android shares you review before sending. | **Open what comes back.** Markdown, images, PDFs, media and supported diagrams, ready to read or share. |

Tap the context ring for usage details. Hold the composer arrow and slide to an available action. The drawer brings together Chats, Activity, Connections, App settings and Hermes administration.

[Explore the feature guide →](docs/FEATURES.md)

## Make room for Wing

1. **Have a host ready.** Android 7.0 or newer and a compatible Hermes server reachable from your phone.
2. **Install the app.** Choose a signed APK from [Releases](https://github.com/tarkilhk/wing/releases), when available. Most current phones use ARM64. Release notes identify published builds.
3. **Connect and say hello.** Follow [Getting started](docs/GETTING_STARTED.md) to start the authenticated dashboard, add a connection and verify your first chat.

The modern dashboard and Desktop Gateway are required. An API key for the older API-only transport is not sufficient. Use HTTPS or an encrypted private network for remote access.

### Know what stays connected

Local notifications need an active connection and do not cover every unopened chat. Queues drain while the client is running and connected. If the app closes while sending, check server history before resending a recovered draft.

There is no offline conversation archive or general remote filesystem browser. Bots and Cron/messaging/webhook administration are outside the current scope. [Known limitations](docs/KNOWN_LIMITATIONS.md) covers recovery and backend restrictions; the [product plan](docs/PRODUCT_PLAN.md) separates future work from delivered features.

## A little wing, everywhere

The wink, the messenger wing, and three pointed feathers above the **i**. One small shape connects the wordmark to the rest of the identity.

<p align="center">
  <a href="docs/design/2026-09-15-wing-identity.md"><img src="docs/design/images/wing-identity-board.png" alt="Approved Wing identity board showing the portrait, lowercase wordmark with compact feather accents, single-wing emblem, navy cream mint palette, and brand application concepts" width="900"></a>
</p>

The approved brand board shows identity concepts. The screenshots above show the app. [Identity rules and artwork](docs/design/2026-09-15-wing-identity.md) · [Studio design system](docs/DESIGN_SYSTEM.md)

## Build with us

Use Flutter 3.44.0 with its bundled Dart SDK, Java 17 and Android SDK platform 36, matching CI.

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

On Windows, use the guarded launcher in [Contributing](CONTRIBUTING.md). Run tests and Android builds sequentially. Live-server tests are opt-in and can create or change server data; read their prerequisites first.

[Contributing](CONTRIBUTING.md) · [Release instructions](docs/ANDROID_RELEASE_PLAN.md) · [Changelog](CHANGELOG.md) · [Documentation index](docs/README.md)

<details>
<summary>App identity and the repository name</summary>

Wing was previously labelled Hermes Personal. The approved wordmark uses lowercase **wing**; the app name is **Wing**, or **Wing Dev** for development builds.

- Release package: `com.tarkilhk.hermes.android`.
- Development package: `com.hermesagent.hermes_android.dev`.
- Package IDs and signing identity stay the same for in-place updates.
- The repository is now `tarkilhk/wing`, renamed from `tarkilhk/hermes-android`.
- The inherited upstream application has a separate package and signing identity.

[pubspec.yaml](pubspec.yaml) declares the source version. App settings shows the installed version. Source changes do not imply a published APK.

</details>

## Support and provenance

Found a client problem? [Open an issue](https://github.com/tarkilhk/wing/issues) with reproducible steps, following the [redaction guidance](SECURITY.md). The [privacy policy](PRIVACY.md) covers storage, server processing, dictation and deletion, and is available offline in App settings.

Wing is an independent fork of [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android). Inherited contributors include CarlosReyesPena, CristianGCiocoi, AI-Guru, grunjol, louquillio and sternbergm. [NOTICE.md](NOTICE.md), the changelog and Git history preserve attribution.

MIT, following upstream. See [NOTICE.md](NOTICE.md) for attribution and third-party notices.
