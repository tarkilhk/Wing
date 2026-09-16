# Play data safety preparation

This inventory describes Wing (`com.tarkilhk.wing`) as checked on 17 September 2026. It is preparation for Play Console, not a submitted declaration or a claim that Google has accepted the app. Recheck it against the final bundle and its merged manifest before submission.

Read Google's [Data safety form guidance](https://support.google.com/googleplay/android-developer/answer/10787469) and [User data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en). Off-device transmission can be collection even when the destination is not the developer's server. Assess collection and sharing separately: a user-initiated sharing exception does not automatically exempt collection. Data processed only on the device is outside the collection disclosure scope until it is transmitted. Do not select "no data collected" solely because this app connects to a self-hosted server.

## Source inventory

| Flow | Data and destination | Source |
| --- | --- | --- |
| Connection authentication | Dashboard username/password, session cookies, WebSocket tickets and custom access headers to the chosen server/proxy | `connection_manager.dart`, `profile_gateway.dart` |
| Chat and agent actions | User messages, selected files, profile/session identifiers and requested operations to Hermes and its configured services | `profile_workspace_controller.dart`, `attachment_draft_service.dart` |
| Administration | Explicitly entered provider keys, profile content and configuration to Hermes | `administration_repository.dart` and administration screens |
| Voice dictation | Local: explicitly on-device Android recognition. Hermes: recorded audio sent to the selected server profile and its speech provider; transcript returned to the draft | `android_voice.dart`, `hermes_voice.dart`, native `VoiceCapture.kt` |
| Read aloud | Local: installed offline Android voice. Hermes: reply text sent to the selected profile's speech provider and synthesized audio returned for phone playback | `hermes_voice.dart`, native `VoicePlayback.kt` |
| Local persistence | Passwords, saved API keys and custom access headers in secure storage; connection metadata including usernames, settings, drafts, queues and recovery references in private app storage | `connection_manager.dart`, `composer_draft_store.dart`, `gateway_turn_journal.dart` |
| Configuration backup | Connections, credentials and settings written to a private temporary file and passed to the app selected in the share sheet; encrypted only when a passphrase is supplied | `config_backup.dart`, `config_backup_service.dart`, `config_backup_io.dart` |
| File sharing/viewing | Selected downloaded bytes passed to the selected external app | `android_file_delivery_service.dart`, native `MainActivity.kt` |
| Remote images and web links | Requests to the referenced image host or browser destination | Message image widgets and `web_preview.dart` |
| Notifications and background monitoring | Authenticated Hermes event connections remain active while chats are working; Android receives local alerts with chat names, connection/profile and optional message excerpts on by default | `turn_notification_service.dart`, `background_monitoring_service.dart`, native `BackgroundMonitoringService.kt` |

Source paths above are under `lib/core/services/` unless otherwise stated. Native sources are under `android/app/src/main/kotlin/com/tarkilhk/wing/`. There is no advertising or app analytics configuration in this build. `pubspec.yaml` and `pubspec.lock` contain no Firebase dependencies. Wing does not register with a push provider or transmit device push tokens. Notifications use local Android delivery and direct connections to Hermes. Voice input/output are separately selected in App settings. Local processing never switches automatically to Hermes or an Android network voice. Hermes processing sends audio or reply text to the selected profile's configured services. Temporary phone audio is deleted on completion/cancellation/failure; process-death leftovers are removed on the next activity creation. Provider retention is separate.

## Decisions to verify for the final artifact

- Map messages, files/images, identifiers and any SDK activity to the current form's data categories and purposes. Evaluate whether each flow is required or optional for the app's functionality.
- Check the actual speech-recognition and browser behavior on supported devices, including any system-service exceptions in Google's guidance.
- Confirm every destination and its retention. Hermes history can be persistent; do not describe all processing as ephemeral.
- Do not claim that all collected data is encrypted in transit while the client accepts plain HTTP. HTTPS does not establish the end-to-end encryption exception: Hermes and its configured providers can read the content they process. Google's User Data policy requires secure transmission of personal and sensitive data; documenting HTTP support does not resolve that implementation concern.
- Describe local deletion and server deletion separately. Clearing Android storage does not erase Hermes or provider data. This client creates no account with its maintainer.
- Inspect the merged manifest and final bundle's libraries. Confirm that the absence of advertising, analytics and push SDKs matches the artifact being uploaded. Reassess this inventory whenever dependencies or data flows change.

## Privacy policy publication

[PRIVACY.md](../PRIVACY.md) is the policy source and the bundled offline policy shown in App settings. Publish it at an active public URL that requires no sign-in, is not geofenced, is not a PDF, and cannot be edited by visitors. Enter that URL in Play Console and verify it while signed out. Confirm that the policy names Wing and provides a working privacy inquiry route. Keep the hosted and bundled text consistent for the release.

The policy describes existing behavior. It does not replace any required in-app disclosure and consent, the foreground-service declaration, or the AI-generated-content safeguards and in-app reporting flow. Those app and submission requirements need separate validation before release.

The repository change supplies the policy and in-app access. Hosting, the Play Console URL, Data safety answers and reviewer-access configuration remain publication steps. No Play account or console state has been changed by this work.
