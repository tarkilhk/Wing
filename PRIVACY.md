# Wing privacy policy

Effective date: 17 September 2026.

This policy covers Wing (`com.tarkilhk.wing`), maintained by [tarkilhk and the Wing contributors](https://github.com/tarkilhk/wing). It is an independent Android client for a Hermes server you choose. The app does not require an account with Wing's maintainer. Your Hermes host, model providers, and services used by your agent have their own data practices.

## Data the app handles

- **Server address, connection label, username, password, saved API keys and custom access headers.** Connect and authenticate to your chosen Hermes server or access proxy. Passwords, saved API keys and custom access credentials use Android Keystore-backed secure storage. Connection labels, addresses and usernames are stored in app preferences. Credentials are read into memory when needed to connect.
- **Messages, agent replies, tool activity and session information.** Display and manage your conversations. Submitted messages go to the selected Hermes server, which may send them to its configured model providers and tools. The phone loads conversation history from that server.
- **Draft text, follow-up queues and staged attachments.** Keep work you have not sent across app restarts. The app stores these in its private device storage. Selected images are processed to remove embedded metadata before upload; other files can retain their original contents and metadata.
- **Files, images, camera captures, clipboard images and Android shares you select.** Prepare attachments for review and upload to the selected chat when you send. Uploads include attachment names and file types. Removing image metadata does not remove personal information visible in the image or its filename. Incoming shares are retained until you choose what to do with them. The app does not automatically send them.
- **Microphone input and recognized text.** You choose Local or Hermes voice input in App settings. Local uses Android's explicitly on-device recognizer; Wing does not upload the recording. Hermes sends your recording to the selected server profile, which processes it with its configured speech provider. Recordings are limited to two minutes. Temporary phone recordings are removed after capture, cancellation or a failure; files left by process termination are removed on the next activity creation. Transcribed text stays in your editable draft until you send it. Wing does not silently change processing engines.
- **Spoken replies.** Read aloud uses the independently selected output engine. Local uses an installed offline Android voice. Hermes sends reply text to the selected profile's speech provider and downloads synthesized audio for playback on the phone. Temporary playback files are removed when playback ends, stops or fails, or on the next activity creation after process termination. Hermes and its providers control retention on their systems.
- **Settings and recovery references.** Remember appearance, notification preferences, selected connections/profiles, and the session identities needed to reopen work. Recovery references do not form a separate local conversation archive.
- **Provider credentials and sensitive responses you enter in administration or a server request.** Send the requested value to the selected Hermes host for the operation you choose. Sensitive request forms keep these values out of the app's ordinary drafts and transcript. The server controls subsequent use and retention.

The maintainer does not operate a relay for these conversations. The app has no advertising or app analytics service configured in its standard build, and the maintainer does not receive your conversations through the app. If you send information to the maintainer through a support channel, that channel receives what you choose to send. The app does not sell your data.

## Notifications and other services

Wing creates notifications locally from connected Hermes sessions. Alerts include the chat name and connection/profile. Message previews are on by default and can be disabled in App settings; disabling previews leaves the chat name and short status. Previews use reply, question or approval-description text. Secure-input requests and failures use fixed text, without secret values or raw errors. Notifications use private lock-screen visibility; Android controls whether private content is shown or replaced with generic system text.

Background monitoring keeps these authenticated connections running with an ongoing notification and a partial wake lock. It uses additional battery; settings offer an Android battery-optimization exemption for screen-off delivery. Monitoring starts automatically when a chat is working, Android notifications are allowed and at least one alert category is enabled. When no chats are working, it stops after posting any final reply or question notification; those notifications remain visible. Disabling both alert categories in app settings stops monitoring. Force-stop, process termination and network loss can interrupt alerts. Wing does not use Firebase or transmit device push tokens to a push provider.

Remote images displayed in messages can contact the image host. Opening a web link contacts that website through your browser. Opening or sharing a downloaded file with another app gives that app the file you selected. Those websites and apps apply their own policies. Self-contained HTML and diagram previews restrict external network access.

## Permissions and your choices

Microphone access is requested on first launch, after notifications, and is used only when you start dictation. If declined, the microphone action can request it again. Camera capture opens your device's camera app. Photos, files, clipboard images and shared items are selected through the app or Android controls. Notification permission allows local alerts. You can decline or revoke Android permissions and continue using features that do not require them.

Use HTTPS or an encrypted private network when connecting remotely. A plain HTTP connection does not encrypt your credentials or content in transit. The server address and network protection are chosen by you or your server administrator.

HTTPS protects the connection to your server; it does not prevent that server, its configured model providers or agent tools from reading the content they process. Wing does not provide end-to-end encryption that hides your messages from those services.

## Retention and deletion

Drafts and queues remain in app storage until sent, removed, or cleared. Staged files and downloaded previews can remain in private storage or cache until the app cleans them up or you clear app storage. Removing a connection does not promise deletion of every related local draft or cached file. To remove all local app data, use Android Settings, Apps, Wing, Storage, Clear storage, or uninstall the app. Android's automatic app backup is disabled.

Clearing or uninstalling the Android app does not delete conversations, uploaded files, credentials, or records stored on your Hermes server or its providers. Use the app's server-backed conversation deletion controls where available, and contact the server administrator or provider for their retention and deletion options. There is no separate account with this app's maintainer to delete.

Configuration exports contain saved connections and credentials. A passphrase is optional: providing one encrypts the backup; leaving it blank creates a readable JSON file, including API keys, dashboard passwords and custom access headers. The app writes a temporary copy of the export in its private cache before opening Android's share sheet. Dismissing the share sheet does not immediately delete that copy; you can remove it by clearing Wing's cache or app storage in Android Settings. Exported backups, files saved outside the app, and copies shared to other apps remain wherever you saved or sent them until you delete those copies. Keep the backup passphrase private.

## Contact and policy changes

For general privacy questions, contact the maintainer through [Wing's GitHub issues](https://github.com/tarkilhk/wing/issues). Do not post passwords, private server addresses, personal files or conversation contents publicly. Ask for a private contact route before sharing sensitive details.

For a suspected security vulnerability, use [GitHub's private vulnerability reporting](https://github.com/tarkilhk/wing/security/advisories/new). GitHub processes information you submit through these channels under its own privacy policy.

The effective date above changes when this policy changes. The app bundles the policy so you can read it in App settings without connecting to a server. The repository contains the policy for the source version you are viewing; a different release or independently configured build may have different behavior.
