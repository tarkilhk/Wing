# Provider credential recovery

Integrated with current main on 20 September 2026. Reverified against stock
upstream `76fe8f7f5f68a8c4ff3477b0e3904c3e26245df2`: scoped console authentication
and confirmation frames, credential-list format and refresh targeting,
profile OAuth removal, and managed-file listing/deletion retain the required
contracts. Current `auth list` can append the external-login adoption notice
for Anthropic/Codex; Wing accepts that exact informational suffix while still
rejecting incomplete or ambiguous credential rows. This does not change the
server's adoption setting or add an older-server compatibility path.

The integration preserves current profile-aware nested navigation. Credential
details are rebuilt for an explicitly selected profile; file-removal review
retains its captured credential source and server. Existing Health navigation
and repository recovery stay intact.

Integration validation: Flutter analysis with fatal infos passed; the complete
suite passed 2,545 tests with 12 opt-in tests skipped. The final screen/navigation
run passed 48 tests, including provider ownership after profile switching.
Production-widget captures were inspected at 390 dp/100% and 320 dp/200% in both
themes, including renewal confirmation and reviewed file deletion. Chat recovery
was also inspected in both themes and text sizes with a keyboard inset. The
Android debug APK built successfully. These checks used synthetic credentials
and local protocol fixtures; no real provider account was renewed or removed.

Implemented in Wing after owner approval, 18 September 2026. Client-only; no
Hermes patches, deployment or actual account changes. Target verified against
stock upstream [`9dda4332f80c66994fe0e21197a8065a73a88991`](https://github.com/NousResearch/hermes-agent/commit/9dda4332f80c66994fe0e21197a8065a73a88991).
The [research](../research/2026-09-18-provider-recovery.md) and
[removal follow-up](../research/2026-09-18-provider-removal-followup.md) contain
source evidence. Earlier HTML and static mockups in this directory are design
explorations; the captures below are from the implemented Flutter screens.

## Design decision

The task is to recover or remove the credential where its problem is reported.
We compared actions directly beneath the status with a status card and a separate
Manage credentials menu. Direct actions won: one fewer tap, no repeated identity,
and no recovery hidden in a disclosure. Source details remain subordinate.

```text
Claude Code
Claw / personal

Access token expired
Expiry and short explanation

[ Renew access       ]
[ Sign-in options    ]
  Check status
──────────────────────
Delete saved credentials   >
Shared file on the server
Credential details        v
```

Use existing Studio colors, Roboto, warning/danger tokens, 16 dp gutters and
shared rectangular action controls. The page scrolls and wraps at 200% text.
The primary action follows the credential's capabilities; there is no new visual
language or provider-specific navigation. Expiry means the observed access token
expired, not that renewal failed, the subscription ended or model access failed.

## Supported actions

| Credential | Renewal | Sign-in | Removal |
| --- | --- | --- | --- |
| Claude Code file | Match Anthropic OAuth source `claude_code`; confirm shared effect | Server Claude Code `/login` guidance | Reviewed credential file, if stock file policy permits |
| Hermes Anthropic OAuth | Match `hermes_pkce` | Stock external instructions | Profile OAuth DELETE when catalog permits |
| Nous portal | `device_code` source, excluding free tier | Stock device flow | Profile OAuth DELETE when permitted |
| Codex / xAI OAuth | Match reported pool label or known auth-store source, then stable ID | Stock device flow | Profile OAuth DELETE when permitted |
| MiniMax and other device flows | Only explicitly implemented upstream refresh adapters | Stock device flow | Profile OAuth DELETE when permitted |
| API keys | Replace key through profile key editor | Existing key setup | Existing profile key removal; other sources may remain |
| Other external / unknown credentials | No inferred refresh command | Visible source instructions | External instructions, no inferred file deletion |

Codex's catalog hardcodes `has_refresh_token=false`; its auth-store reader
requires a refresh token. The adapter accounts for this current contract rather
than relying on that field alone. Codex and xAI normally report `pool:<label>`;
Wing matches that label within a freshly listed profile pool. If multiple entries
match, the user chooses a label/source/stable ID. This selects a saved credential,
not an inferred account identity. A changed source refuses the operation.

A shared pattern chooses actions from flow, disconnect capability and verified
source adapters. Adding another file deletion adapter requires evidence of its
credential authority; arbitrary external commands never become delete actions.

## Scope and execution

- Capture connection, canonical profile and provider when entering. Remove the
  obsolete Manage shared account/default redirect and root-inheritance claims.
- Renew through stock `/api/console?profile=<canonical>` using existing gateway
  ticket/session authentication and access headers. Wait for a matching ready
  profile. Only permit `auth list` and `auth refresh` for supported provider IDs.
- Parse complete current-format listings. Reject malformed rows, truncation,
  duplicate IDs, ambiguous fields and ID/label/index collisions. Never target
  a positional index or silently choose another credential.
- Re-read the source and list before renewal, retain the stable ID, and confirm
  only the exact submitted command after the console's confirmation-complete
  frame. Use a bounded exchange with no reconnect/replay of a mutation.
- Re-read catalog status afterward. Command completion does not prove model or
  billing readiness; unchanged expiry and unavailable status remain explicit.
- Check status requests the catalog; Wing does not submit a forced refresh or
  a model request for this action. Some upstream status helpers themselves select
  or resolve credentials and may perform automatic renewal.
- Supported device flows retain the returned session during network failures;
  expired/denied sessions expose Start again. Copy code and browser failure
  recovery are visible. Starting sign-in never first deletes old credentials.
- Removal of Hermes-managed OAuth uses the existing profile DELETE, which can
  clear all this provider's saved sign-ins in that profile. The confirmation says
  so; the UI does not claim it deletes only one pool entry or revokes an account.

## Claude file deletion

The catalog's default path does not establish the physical source: Claude Code
may use `CLAUDE_CONFIG_DIR` or the OS keychain. The user reviews the file location
and confirms it is the file in use. Wing lists directory metadata only, never
reads the credential contents, and requires the exact `.credentials.json` file.

Check file resolves the canonical path. Final confirmation identifies the server,
path and shared effect. Before deletion, Wing rereads the catalog and file
size/mtime; changed metadata refuses deletion. The stock DELETE is nonrecursive
and server-scoped, with no selected-profile parameter. Server file-root denials
remain denials, with instructions to remove the sign-in on the server.

Deletion removes that file. It does not revoke issued tokens, delete the provider
account, clear in-memory/pool copies, or remove a separate keychain sign-in.
Deleting only a pool row is intentionally not called Disconnect: Hermes can read
Claude Code's file again. Stock Hermes has no conditional file DELETE or atomic
catalog-to-pool comparison; the rechecks reduce but cannot eliminate a concurrent
source change between checking and mutation. CLI source display also strips
`manual:` prefixes; unusual imported source aliases are not a stronger authority
than the current catalog and listing.

## Review and validation

Native Flutter screen captures are generated by
`test/provider_recovery_screen_test.dart` with `CAPTURE_PROVIDER_RECOVERY=true`
and `CAPTURE_FONT_DIR` containing Roboto, MaterialIcons and monospace fonts.
Inspected 390×844 normal text and 320×844 at 200% in both themes, including
confirmation, file review, loading, failure and credential choice. The initial
spinner continued behind a confirmation; it now pauses during user review.

- [Implemented dark screen](images/provider-recovery-implemented-dark.png)
- [Implemented light screen](images/provider-recovery-implemented-light.png)

Tests cover console scope/confirmation/timeouts, stable credential targeting,
changed sources and files, unknown capabilities, partial completion, confirmed
shared deletion, captured profile removal, device-flow restart and large-text
reachability. No live provider exchange or deletion was used for validation.

Final checks: `flutter analyze --no-pub` clean; 32 focused recovery tests pass;
45 recovery-screen/navigation tests pass without screenshot fonts; debug APK
build succeeds. The full regression run had 2,201 passing and 12 skipped tests,
with three failures from obsolete navigation expectations and large-text test
hit targets; all three were corrected and passed in the 45-test rerun. The full
suite was not repeated after that targeted rerun. Build output retains an existing
Flutter advisory about Android plugins using Kotlin Gradle Plugin.
