# Play data safety preparation

This is a source-backed inventory for the person completing Play Console. It is not a submitted declaration or a claim that Google has accepted this app. Recheck it against the final bundle, including any build-time Firebase configuration.

Read Google's [Data safety form guidance](https://support.google.com/googleplay/android-developer/answer/10787469) and [User data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en). Off-device transmission can be collection even when the destination is not the developer's server. User-initiated sharing exceptions and system-service rules need to be assessed for the actual flow. Do not select "no data collected" solely because this app connects to a self-hosted server.

## Source inventory

| Flow | Data and destination | Source |
| --- | --- | --- |
| Connection authentication | Dashboard username/password, tokens and custom access headers to the chosen server/proxy | `connection_manager.dart`, `profile_gateway.dart` |
| Chat and agent actions | User messages, selected files, profile/session identifiers and requested operations to Hermes and its configured services | `profile_workspace_controller.dart`, `attachment_draft_service.dart` |
| Administration | Explicitly entered provider keys, profile content and configuration to Hermes | `administration_repository.dart` and administration screens |
| Voice dictation | Audio processed by the Android speech-recognition service; transcript returned to the draft | `voice_composer_adapter.dart` |
| Local persistence | Credentials in secure storage; connection metadata, settings, drafts, queues and recovery references in private app storage | `connection_manager.dart`, `composer_draft_store.dart`, `gateway_turn_journal.dart` |
| File sharing/viewing | Selected downloaded bytes passed to the selected external app | `android_file_delivery_service.dart`, native `MainActivity.kt` |
| Remote images and web links | Requests to the referenced image host or browser destination | Message image widgets and `web_preview.dart` |
| Notifications | Local session-derived alerts; titles optional | `turn_notification_service.dart` |
| Optional custom push build | Messaging token, installation identifier and notification settings to Firebase and the configured server | `background_push_service.dart` |

Source paths above are under `lib/core/services/` unless otherwise stated. There is no advertising or app analytics configuration in the standard build. Firebase packages remain, but initialization requires explicit build options. Do not reuse the standard-build declarations for an independently configured push build.

## Decisions to verify for the final artifact

- Map messages, files/images, identifiers and any SDK activity to the current form's data categories and purposes. Evaluate whether each flow is required or optional for the app's functionality.
- Check the actual speech-recognition and browser behavior on supported devices, including any system-service exceptions in Google's guidance.
- Confirm every destination and its retention. Hermes history can be persistent; do not describe all processing as ephemeral.
- Review the encryption-in-transit answer carefully. The client accepts plain HTTP, so the repository does not establish encryption for every possible connection.
- Describe local deletion and server deletion separately. Clearing Android storage does not erase Hermes or provider data. This client creates no account with its maintainer.
- Inspect the merged manifest and final bundle's libraries. Verify that the documented Firebase-disabled behavior matches the artifact being uploaded.

## Privacy policy publication

[PRIVACY.md](../PRIVACY.md) is the policy source and the bundled offline policy shown in App settings. Publish a publicly accessible, readable version and enter its final URL in Play Console. Confirm that it identifies the app/publisher and a usable privacy contact. Keep the hosted and bundled text consistent for the release.

The repository change supplies the policy and in-app access. Hosting, the Play Console URL, Data safety answers and reviewer-access configuration remain publication steps. No Play account or console state has been changed by this work.
