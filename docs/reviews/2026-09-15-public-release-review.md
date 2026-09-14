# Public release review, 2026-09-15

I would fix the credential redirect and the two reproduced send/queue bugs before inviting a broad audience. Google Play also needs privacy disclosures and a verified store artifact.

This is a review, not a remediation patch. P1 means address before public distribution; P2 means a substantive defect or release preparation gap; P3 means documentation cleanup. Priorities describe this release decision, not a claim of a formal security rating.

This is the original review snapshot. See [the follow-up cleanup](../DOCUMENTATION_CLEANUP_2026-09-15.md) for fixes and corrected assessments.

## Scope and verification

The review began at `f0927afab49cb6be2137ecc7bd121263888c9bb0`, version `2.36.8+2225`, with an existing edit to `lib/main.dart`. Another task committed `07073ce8748dee6ee85b8a81b6919fb6f34ee25c`, version `2.36.9+2226`, during the review. Further theme edits appeared afterward. This was a changing checkout, not a frozen release-candidate certification. The reviewed transport/controller paths remained unchanged during the probes.

Reviewed areas include the public README and documentation index, product contracts, release configuration and CI, Android manifest/native preview boundaries, credential storage and transport, configuration backup, and draft/queue recovery. Separate standards and specification reviews informed the findings below. Historical documents were sampled and checked through the index; this is not a line-by-line review of every archived research note or every source file.

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub --fatal-infos` | Passed, no issues |
| `flutter test --no-pub --reporter=expanded` | 1,634 passed, 10 skipped |
| Cross-origin redirect regression probe | Failed as expected, synthetic session credential reached the destination |
| Process-death recovery regression probe | Failed as expected, recovered uncertainty false and error null |
| Queued-image ownership regression probe | Failed as expected, deleted cache and one image upload for two submissions |
| `flutter pub outdated` | Completed; 33 upgradable dependencies locked to older versions and 13 constrained below a resolvable version |
| `flutter build apk --release --split-per-abi` | Blocked by the repository's build lock because another Hermes Android build was running |
| Root README and documentation-index relative links | Resolve |
| Targeted tracked-file private-key/token pattern scan | No matches; not a complete secret scan or Git-history audit |

The three probes are retained locally under `.dart_tool/review_probes/` and are ignored by Git. Run them with `flutter test --no-pub .dart_tool/review_probes --reporter=expanded` after other Android builds finish. They use synthetic data and existing fixtures. The process-death test recreates the controller from persisted preferences while leaving the old acknowledgement unresolved; it does not kill a physical Android process. The image probe verifies client ownership and RPC behavior with a fixture, not a live Hermes server.

Temporary logs are `hermes-release-review-tests.log`, `hermes-release-review-outdated.log`, and `hermes-release-review-build.log` in the Windows temporary directory. No app was installed, signed for distribution, or published. Existing and concurrently produced edits were preserved.

## Standards

### S1. Withdrawn: licensing blocker

The initial review incorrectly treated an inherited notice in this fork as grounds to question upstream's MIT identification. That was not sufficient evidence of a distribution blocker. Upstream's README identifies MIT, and the user corrected the attribution. The documentation retains MIT and the misleading warning has been removed. No upstream license withdrawal is established.

### S2. P2: Update the README's descriptions of current controls

[README.md:26](https://github.com/tarkilhk/hermes-android/blob/f0927afab49cb6be2137ecc7bd121263888c9bb0/README.md#current-implementation) calls the context indicator a thin fuse, while production uses `ContextRing`. Line 29 describes Send/Stop long-press behavior without the held-slide selector and busy Steer default documented in [COMPOSER_ACTION_GESTURE.md](../COMPOSER_ACTION_GESTURE.md). This conflicts with the documentation index's rule that README describes current implementation. Align the user instructions with the delivered controls.

### S3. P2: Provide a reproducible installation-to-first-chat guide

[README.md:45](https://github.com/tarkilhk/hermes-android/blob/f0927afab49cb6be2137ecc7bd121263888c9bb0/README.md#connect-to-hermes) requires modern dashboard/profile APIs and an authenticated Desktop Gateway, then starts with “Run Hermes.” It supplies neither a tested backend revision nor a direct backend launch/setup procedure for those mandatory services. An unfamiliar user cannot reproduce the author's environment from this guide alone.

Document one tested backend installation and launch path, exact supported version or revision, networking/authentication example, and first-chat check. Keep LAN/private-network and public HTTPS instructions explicit. Link other deployments as alternatives once tested.

### S4. P3: Correct current wording in the release guide

[ANDROID_RELEASE_PLAN.md:77](https://github.com/tarkilhk/hermes-android/blob/f0927afab49cb6be2137ecc7bd121263888c9bb0/docs/ANDROID_RELEASE_PLAN.md#first-private-release) says the workflows “currently” pin base code 2141. They now pin 2226. Label the old numbers as historical examples or derive the instructions from the current source. The initial README ARM64 mismatch was corrected by the concurrent 2.36.9 change and is no longer an open finding.

The licensing blocker was withdrawn. The three documentation findings above describe the original review snapshot; see the cleanup record for completed fixes. No standalone code-smell findings are asserted.

## Spec

### B1. P2: Persist uncertainty before dispatching a normal send

In [profile_workspace_controller.dart:3808](../../lib/core/services/profile_workspace_controller.dart), `_sendPrompt` persists the draft with its existing false uncertainty flag. It sets that flag only after an exception at lines 3895-3897. Process death after `prompt.submit` reaches Hermes but before acknowledgement skips that exception handler. Restoration at lines 2783-2798 then presents the retained submitted text as an ordinary unsent draft.

The probe recreates the controller with completed server history and the same persisted preferences. The retained draft reports `draftSubmissionUncertain == false` and `error == null`. A user can submit the same work again without the promised warning. This violates the distinction between uncertain and unsent work in [PRODUCT_PLAN.md:244](../PRODUCT_PLAN.md#storage-and-recovery-boundary).

Persist a submission-in-progress/uncertain marker before dispatch. Clear it after acknowledgement or a definitive rejection, while preserving any newer composer text. Reconcile on recovery without automatic duplicate submission.

### B2. P2: Keep queued attachments independent of an unacknowledged send

[profile_workspace_controller.dart:3983](../../lib/core/services/profile_workspace_controller.dart) moves the visible attachment objects into a queued prompt. During acknowledgement latency, `_sendPrompt` still owns those same objects. [profile_workspace_screen.dart:1432](../../lib/core/screens/profile_workspace_screen.dart) permits Queue in this state. The first send's cleanup at controller line 3893 deletes the queued image's cached bytes. Its retained runtime attachment receipt then makes the follow-up skip a fresh `image.attach_bytes` call.

The probe sends an image, delays acknowledgement, types and queues a follow-up, then acknowledges and resumes the queue. The cache no longer exists, and two `prompt.submit` calls produce only one image attachment call. This violates the independently owned draft/queue attachment contract in [PRODUCT_PLAN.md:242](../PRODUCT_PLAN.md#storage-and-recovery-boundary).

Reserve attachments for the in-flight send, disable moving those attachments during acknowledgement, or create independent queued ownership with a fresh upload receipt. Add a regression covering this transition, including restart before queue delivery.

Spec findings: two, both reproduced P2 defects. The attachment ownership race is the more direct loss of queued content.

## Security and distribution

### R1. P1: Stop authenticated requests from forwarding session tokens across origins

[connection_manager.dart:1173](../../lib/core/services/connection_manager.dart) wraps HTTP in `_NoRedirectClient` only when custom gateway headers are present. With ordinary session-token authentication and no custom headers, `apiGet` at line 1335 follows redirects using `X-Hermes-Session-Token`. That custom header is forwarded to a different origin.

A local two-server probe fetched a synthetic token from `127.0.0.1`, redirected the profile API request to `localhost` on a different port, and observed the token at the destination. The protection currently tested for custom access-proxy headers does not protect the app's own token in the ordinary path. Exploitation requires a redirect from the configured endpoint or its network/proxy path; this is not evidence of a production compromise.

Disable redirects for every authenticated request, or enforce an explicit same-origin policy that never forwards secrets on an origin or scheme change. Add regression coverage for ordinary token authentication alongside the custom-header test.

### R2. P2: Bound connection discovery and file-download requests

[connection_manager.dart:1198](../../lib/core/services/connection_manager.dart) and lines 1243, 1335 and 1357 perform login/token/API/download requests without deadlines. [profiles_repository.dart:86](../../lib/core/services/profiles_repository.dart) awaits discovery directly. The connection form awaits `repository.probe()` at [main.dart:1337](../../lib/main.dart) without a timeout. A server that accepts the connection and never supplies the response can leave Save spinning indefinitely. File download streams can likewise remain pending if the server stops sending without closing.

The timeout test currently targets legacy `ApiClient.getSessions`; it does not cover this active dashboard path. Some callers, such as administration and ProfileGateway, add deadlines, but the connection form and remote-file client do not. Add connection, response and stream-idle deadlines at the transport boundary and ensure cancellation releases the request. This finding is source-verified; no additional hanging-server probe was run.

### R3. P1 for Play submission: Add privacy documentation and an in-app entry

No privacy policy, policy URL or in-app privacy entry was found in the tracked repository or active app settings. [SECURITY.md](../../SECURITY.md) only describes redacting diagnostics. It does not explain handling of credentials, conversation content, uploaded files, microphone input, local drafts, or the services that process those data.

Google Play requires a privacy policy in Play Console and a policy link or text inside the app, plus accurate Data safety disclosures. See Google's [User data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en-GB). Document actual behavior, including the device speech-recognition service and any SDKs retained in the shipping artifact. Do not assume “self-hosted” makes disclosure unnecessary. Play Console itself was not inspected.

### R4. P2: Replace the stale store description

[full_description.txt:8](../../fastlane/metadata/android/en-US/full_description.txt) advertises text-to-speech, Read Aloud, Export, Cron Jobs and background notifications without the limitations documented in the current README. Cron administration is explicitly outside selected scope. The README also says local notifications need an active connection and have limited unopened-chat coverage.

Rewrite the listing against reachable, verified functionality. In particular, explain that this is a client requiring a separately running compatible Hermes installation and state notification limits before users install it.

### R5. P2 if retained for distribution: Correct or retire the F-Droid recipe

[fdroiddata.yml:6](../archive/fdroiddata.yml) still points source, issues and build repository at `rusty4444/hermes-android`, with a 2.0.1 tag. It therefore describes the inherited application, not this fork. Its output at line 20 expects an ARM64 split APK while line 29 builds without `--split-per-abi`.

Either explicitly archive this inherited recipe or update it for this fork and verify a matching artifact. Keep inherited attribution while distinguishing the current publisher, support destination and package identity.

Security/distribution findings: five. The reproduced credential forwarding is the most serious implementation finding within this group.

## Remaining release evidence and cleanup

The successful analysis and tests are useful evidence, but they do not establish that the latest APK/AAB is ready. The build was blocked by another build, and new theme edits appeared after the suite. A final release candidate needs sequential analysis/tests/build against a fixed revision, followed by physical-device release-mode checks for first connection, send/reconnect, process death, attachments, notifications and settings migration.

The existing release workflow produces APKs, not a Play-tested App Bundle. Prepare and verify the AAB, signing arrangement, upgrade path from ABI-split APK version codes, and native-library/page-size compatibility. Google's [page-size guidance](https://developer.android.com/guide/practices/page-sizes) describes artifact and device checks. This review did not verify a packaged artifact or inspect Play Console configuration.

The dependency check also reports `flutter_markdown` as discontinued in favor of `flutter_markdown_plus`. Record a migration decision and review relevant dependency changes; newer versions alone are not evidence of vulnerabilities and are not a reason for an untested bulk upgrade. Firebase packages remain despite the documented dropped delivery plan, which deserves a deliberate remove-or-retain decision before final data disclosures.

For public presentation, shorten README's implementation inventory into a short overview, screenshots, setup, known limitations and contributor instructions. Keep detailed delivery records in the docs index. Historical research links to deleted source files should use commit-pinned references. These are editorial improvements, not additional release blockers.

The next implementation pass should address the three reproduced bugs with permanent regression tests, preserve MIT attribution, and prepare a user-facing setup guide and truthful store/privacy documentation. Keep UI redesign and broad architecture changes separate so release fixes remain reviewable.
