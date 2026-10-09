<p align="center">
  <img src="docs/design/images/wing-readme-hero-tagline.png" alt="Wing — Your agent, with you" width="720">
</p>

# Wing for Android

Wing is a free, independent, open-source Android companion for [Hermes Agent](https://github.com/NousResearch/hermes-agent). Pick up a conversation, follow live work, and steer the next step when you leave your desk. Your agent runs on your Hermes server; Wing brings its workspace to your phone.

[**Download Wing**](https://github.com/tarkilhk/Wing/releases/latest) · [Get connected](docs/GETTING_STARTED.md) · [Explore the features](docs/FEATURES.md)

Every feature is included without a Wing subscription. Your server and model providers may have their own costs.

**You need:** Android 7.0 or newer and a reachable Hermes server with its dashboard, Desktop Gateway and a configured model provider. [Connection guide](docs/GETTING_STARTED.md).

<p align="center">
  <img src="website/assets/screenshots/conversation-dark.png" alt="Wing conversation with a research comparison, a formatted table and the message composer" width="285">
  <img src="website/assets/screenshots/steer-dark.png" alt="Wing's held composer action menu with Steer selected during live work" width="285">
</p>

<p align="center"><em>Real Wing interfaces, shown with demo content.</em></p>

## Keep the work moving

- Follow streaming replies, tool activity, delegated tasks and available reasoning. Steer live work, queue a follow-up, or stop a run.
- Find conversations across profiles and projects. Search, pin, group, and use Recents to catch up on ongoing work.
- Bring photos and files from Android. Dictate into an editable draft, read replies aloud, and save or share output files.
- Read code and tables, preview reports and supported media, and keep unsent drafts and staged files across navigation and restart.
- Manage supported profiles, models, connectors and scheduled tasks. Check health, run diagnostics, and explore token usage.

[Full feature guide](docs/FEATURES.md) · [Current limitations](docs/KNOWN_LIMITATIONS.md)

## Get connected

1. Make your Hermes dashboard and Desktop Gateway reachable from your phone. Use HTTPS or an encrypted private network for remote access.
2. Install a signed APK from the [latest release](https://github.com/tarkilhk/Wing/releases/latest). Choose **arm64-v8a** for most current phones; releases list other architectures and checksums.
3. Follow the [setup guide](docs/GETTING_STARTED.md), choose a profile, and send your first message.

The [self-hosting guide](docs/SELF_HOSTING.md) covers dashboard access and proxy setup. A model-provider API key alone is not enough to connect Wing.

## Your server, your conversations

The maintainer does not relay your conversations. Your chosen Hermes server and model providers process your content. [Privacy policy](PRIVACY.md).

Work accepted by Hermes can continue when your phone disconnects. Sending new messages and controlling live work need a connection. Notifications use live connections and can be interrupted by Android restrictions or network loss. [Notification guide](docs/NOTIFICATIONS.md).

[Configuration backups](docs/CONFIGURATION_BACKUPS.md) save connections, saved credentials and supported preferences, with optional passphrase encryption. Conversations stay on Hermes; drafts and queues are excluded.

This README describes the current source. Check your APK's [release notes](https://github.com/tarkilhk/Wing/releases/latest) for shipped changes.

## Support Wing

If Wing makes your Hermes setup more useful, you can help fund its development. Support is optional; every feature is available either way.

[Sponsor on GitHub](https://github.com/sponsors/tarkilhk) · [Buy me a coffee](https://ko-fi.com/tarkil)

## Help and contribute

[Report an issue](https://github.com/tarkilhk/Wing/issues) with reproducible steps, following the [redaction guidance](SECURITY.md).

Wing builds on the open-source work of [rusty4444](https://github.com/rusty4444) and the Hermes Android contributors. Licensed under [MIT](LICENSE). See [NOTICE.md](NOTICE.md) for credits and third-party notices.

[Contribute](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) · [Documentation](docs/README.md)
