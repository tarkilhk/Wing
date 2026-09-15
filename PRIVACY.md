# Wing privacy policy

Effective date: 15 September 2026.

This policy covers Wing, maintained in the `tarkilhk/wing` repository. It is an independent Android client for a Hermes server you choose. The app does not require an account with this fork's maintainer. Your Hermes host, model providers, and services used by your agent have their own data practices.

## Data the app handles

- **Server address, connection label, username, password and custom access headers.** Connect and authenticate to your chosen Hermes server or access proxy. Passwords and custom access credentials use Android's secure storage. Connection labels and addresses are stored in app preferences.
- **Messages, agent replies, tool activity and session information.** Display and manage your conversations. Submitted messages go to the selected Hermes server, which may send them to its configured model providers and tools. The phone loads conversation history from that server.
- **Draft text, follow-up queues and staged attachments.** Keep work you have not sent across app restarts. The app stores these in its private device storage. Selected images are processed to remove embedded metadata before upload; other files can retain their original contents and metadata.
- **Files, images, camera captures, clipboard images and Android shares you select.** Prepare attachments for review and upload to the selected chat when you send. Incoming shares are retained until you choose what to do with them. The app does not automatically send them.
- **Microphone input and recognized text.** Dictate a draft when you start voice input. Android's speech-recognition service processes the audio and may use its provider's servers, depending on the device and service settings. The app receives the transcript; you review and send it as a message.
- **Settings and recovery references.** Remember appearance, notification preferences, selected connections/profiles, and the session identities needed to reopen work. Recovery references do not form a separate local conversation archive.
- **Provider credentials and sensitive responses you enter in administration or a server request.** Send the requested value to the selected Hermes host for the operation you choose. Sensitive request forms keep these values out of the app's ordinary drafts and transcript. The server controls subsequent use and retention.

The maintainer does not operate a relay for these conversations. The app has no advertising or app analytics service configured in its standard build, and the maintainer does not receive your conversations through the app. If you send information to the maintainer through a support channel, that channel receives what you choose to send. The app does not sell your data.

## Notifications and other services

Standard builds create notifications locally from connected sessions. Notifications can include chat titles only if you enable that option. Android may display them on your lock screen according to your system settings. Local alerts are not a guarantee of delivery after Android suspends or closes the app.

Firebase messaging code remains in the source but is not initialized in a standard build without Firebase build configuration. A separately configured build can send a device messaging token, an installation identifier and notification preferences to its configured Firebase service and Hermes server. This policy's standard-build description must not be used to describe such a build without updating its disclosures.

Remote images displayed in messages can contact the image host. Opening a web link contacts that website through your browser. Opening or sharing a downloaded file with another app gives that app the file you selected. Those websites and apps apply their own policies. Self-contained HTML and diagram previews restrict external network access.

## Permissions and your choices

Microphone access is used for dictation. Camera capture opens your device's camera app. Photos, files, clipboard images and shared items are selected through the app or Android controls. Notification permission allows local alerts. You can decline or revoke Android permissions and continue using features that do not require them.

Use HTTPS or an encrypted private network when connecting remotely. A plain HTTP connection does not encrypt your credentials or content in transit. The server address and network protection are chosen by you or your server administrator.

## Retention and deletion

Drafts and queues remain in app storage until sent, removed, or cleared. Staged files and downloaded previews can remain in private storage or cache until the app cleans them up or you clear app storage. Removing a connection does not promise deletion of every related local draft or cached file. To remove all local app data, use Android Settings, Apps, Wing, Storage, Clear storage, or uninstall the app. Android's automatic app backup is disabled.

Clearing or uninstalling the Android app does not delete conversations, uploaded files, credentials, or records stored on your Hermes server or its providers. Use the app's server-backed conversation deletion controls where available, and contact the server administrator or provider for their retention and deletion options. There is no separate account with this app's maintainer to delete.

Configuration exports contain saved connections and credentials. A passphrase is optional: providing one encrypts the backup; leaving it blank creates a readable JSON file, including API keys and dashboard passwords. Exported backups, files saved outside the app, and copies shared to other apps remain wherever you saved or sent them until you delete those copies. Keep the backup passphrase private.

## Contact and policy changes

For general privacy questions, contact the maintainer through [this fork's GitHub issues](https://github.com/tarkilhk/wing/issues). Do not post passwords, private server addresses, personal files or conversation contents publicly. Ask for a private contact route before sharing sensitive details.

The effective date above changes when this policy changes. The app bundles the policy so you can read it in App settings without connecting to a server. The repository contains the policy for the source version you are viewing; a different release or independently configured build may have different behavior.
