# Release checklist

Complete this for a fixed release candidate. Record passed, failed or not applicable with a reason in the release notes or pull request. Use the [release guide](ANDROID_RELEASE_PLAN.md) for identity/signing and [Testing](TESTING.md) for live-server prerequisites.

## Automated checks

- [ ] `flutter analyze --fatal-infos` passes.
- [ ] `flutter test` passes; opt-in skips and their coverage limits are recorded.
- [ ] `flutter pub outdated` has been reviewed and update decisions recorded.
- [ ] The intended signed release artifact builds and passes package, version, certificate and non-debuggable checks.

## Behavior and ownership

- [ ] State management and resource lifetimes remain consistent; controllers, timers, streams and sockets are released by their owner.
- [ ] No dead imports or unused assets were introduced.
- [ ] Errors, loading, partial results and uncertain writes remain visible and actionable.
- [ ] Connection/profile/chat ownership survives navigation, late responses and reconnect.
- [ ] Newer draft text/files survive asynchronous sends and queue actions.
- [ ] Light/dark, narrow/wider layouts, enlarged text, keyboard insets and touch targets work for changed screens.
- [ ] Forms validate input and guard duplicate submissions.

## Security and release documents

- [ ] No credentials, signing material or private evidence is committed; logs and release notes are redacted.
- [ ] User-supplied URLs/hosts are validated and authenticated redirect restrictions remain intact.
- [ ] Version and base code agree across pubspec, workflows and release identity assertions.
- [ ] Changelog records product changes; guides and store text match the candidate.
- [ ] Privacy policy and any Play disclosures match the actual artifact's configuration.
- [ ] Relevant licenses and attribution remain included.

## Manual smoke test

- [ ] Connect to a compatible dashboard/Desktop Gateway and browse chats.
- [ ] Send a message, receive a streamed reply, and reopen saved history.
- [ ] Search and delete a disposable test chat.
- [ ] Open Chats, Activity, Connections, App settings and Hermes administration through the drawer.
- [ ] Navigate while preserving the chat/draft; switching profile leaves another client's selection unchanged.
- [ ] Check interruption/recovery, attachments, queue submission and an output viewer.
- [ ] Check local notification posting and target routing, recording background-delivery limits.
- [ ] Record the tested phone/emulator and any unverified server/device scenario.
