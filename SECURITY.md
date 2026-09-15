# Security and support

Use [this fork's GitHub issues](https://github.com/tarkilhk/wing/issues) for reproducible client problems that can be described without disclosing sensitive data. For a vulnerability, use GitHub's private reporting option if it is available. Otherwise ask for a private contact route without posting exploit details or credentials. Do not send this fork's reports to an unrelated upstream issue tracker by default.

Before sharing logs, screenshots or diagnostics:

- Remove passwords, provider/API keys, Authorization and Cookie values, custom access headers, session tokens and WebSocket tickets.
- Replace private hostnames, addresses, profile/session identifiers and conversation content with synthetic examples.
- Remove personal attachments and output files.
- Exclude `key.properties`, keystores, signing credentials and local environment files.

Include the app version/build, Android version, backend revision if known, expected behavior and minimal reproduction steps. Clearly distinguish an actual server result from a fixture or an assumption.

## Connecting safely

Use HTTPS or an encrypted private network for remote access. Plain HTTP does not encrypt credentials or messages. Keep the dashboard authenticated and restrict who can reach it. The app refuses HTTP redirects for dashboard requests; configure the final address and path directly. Custom access-header secrets are stored with connection credentials in Android secure storage.

Only install artifacts from a source you trust. Wing uses `com.tarkilhk.wing` and its own signing identity. Debug builds and unsigned build outputs are not production releases. See [the release guide](docs/ANDROID_RELEASE_PLAN.md).

## Data handling

[PRIVACY.md](PRIVACY.md) describes device storage, server processing, dictation, notifications and deletion. Synthetic credentials in tests are fixtures; real credentials, personal logs and signing material must never be added to the repository.
