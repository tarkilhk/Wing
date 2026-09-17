# Hermes provider and profile ownership: verified 2026-09-17

## Conclusion

Hermes supports provider credentials and model configuration per profile. However, the rule for a profile without its own credentials changed upstream on **2026-09-16 at 21:34:59 UTC / 2026-09-17 at 05:34:59 Singapore time**. Older code could borrow provider state and credential-pool entries from the root/default profile's `auth.json`. Current upstream removes that implicit inheritance. The existing Wing administration design reflects the older behavior, and its wording also generalizes sharing beyond what the older backend actually guaranteed. [Change removing inheritance](https://github.com/NousResearch/hermes-agent/commit/93889b770da3dc641c2ed55eecffef90da9c358f).

No live server version or live account configuration was verified in this investigation. A local checkout is not evidence of the user's deployed version. No backend or application code was changed.

## Evidence baselines

| Evidence | Version / commit | What it establishes |
| --- | --- | --- |
| Current public upstream, fetched during this investigation | `58c6f6fa201c7e3a5a54c6af70031190db01b8ef`, committed 2026-09-17 05:25:33 UTC | Behavior in the inspected current source; not necessarily deployed behavior |
| Latest published GitHub release observed | `v2026.9.14`, published 2026-09-14 16:04:14 UTC | Release publication predates the ownership change; does not identify the user's installed commit |
| Local read-only backend reference, `hermes-voice-backend` | `af4a3eba0a3674633050bf1c41df45f8ed6f0858`, September 15 | Older root-fallback implementation remains present |
| Wing client checkout | `358dcaf5e191ce6bb7c190bd074af349a1e81ebc` | Current client navigation, labels and API calls |
| Previous Wing acceptance documentation | Hermes `0.21.2`, commit `e16f686706b1e0d5334fd1ae82190058d2a19694`, September 13–14 | Historical acceptance baseline only; not a fresh live-server check |

Public references: [inspected upstream commit](https://github.com/NousResearch/hermes-agent/commit/58c6f6fa201c7e3a5a54c6af70031190db01b8ef), [published release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.14). Local client and acceptance findings were supplied by the companion repository investigation and cross-checked against the relevant files where noted below.

## What a profile means

A profile is a Hermes data/configuration directory. In the normal installation layout, `default` is `~/.hermes`; a named profile such as `work` uses `~/.hermes/profiles/work`. `HERMES_HOME` chooses the active home. The canonical ID `default` is distinct from the *currently selected* or sticky CLI profile. Each home can hold its own model configuration, API keys, OAuth state, sessions and memory. The machine dashboard manages these homes through a profile selector. [Official profiles documentation](https://hermes-agent.nousresearch.com/docs/user-guide/profiles).

These concepts should not be collapsed into one “provider setting”:

| Concept | Meaning |
| --- | --- |
| Provider | The service/route used for inference, e.g. OpenRouter, Anthropic or OpenAI Codex |
| Provider definition | Endpoint/configuration for a provider, including custom endpoints in profile `config.yaml`; distinct from choosing it as the default |
| Credential/account | A key or OAuth grant authenticating to that provider; Hermes supports credential pools with multiple entries |
| Model default | The provider and model the profile selects for new work; changing it is different from adding/removing authentication |
| Profile | Owner of the Hermes configuration and local credential files |
| Server/runtime | The running process serving APIs; it may expose operations for several profiles |

Model assignment is stored in profile configuration; authentication is resolved separately. A profile can configure several providers and keep multiple credential entries for a provider. Provider pools carry individual credential identity, source, priority and status. [Model configuration documentation](https://hermes-agent.nousresearch.com/docs/user-guide/configuring-models), [current credential-pool implementation](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/agent/credential_pool.py).

## The behavior that changed

On May 6, upstream introduced a fallback for workers whose named profile lacked authentication: use that profile's provider state/pool if present, otherwise read the root store for that provider. A local pool with entries shadowed the root pool; it was not a merged set of accounts for that provider. Later token-refresh handling wrote borrowed grants back to their owning root store. [Original change, `33bf5f6292f49f109f11fb9c035afae6dcd356e3`](https://github.com/NousResearch/hermes-agent/commit/33bf5f6292f49f109f11fb9c035afae6dcd356e3), [pre-change auth source](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/auth.py).

On September 16, commit `93889b7` removed the root fallback from `_load_provider_state_with_source`, `read_credential_pool`, and their refresh/write paths. Missing local authentication now produces profile-specific setup guidance instead of taking the root's grant. Its added tests cover both “never reads root” and “refresh never writes root.” The update command also gained an audit notice for profiles without credentials. [Removal and rationale](https://github.com/NousResearch/hermes-agent/commit/93889b770da3dc641c2ed55eecffef90da9c358f), [isolation tests](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/tests/hermes_cli/test_auth_profile_isolation.py), [update audit](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/profile_credential_audit.py).

This explains the contradictory conversation: “profiles can inherit the root account” accurately describes the inspected older code; the current docs now describe the new rule. Neither should have been presented as an unqualified statement about the deployed server.

Validation: the companion investigation extracted the exact `_provider_state_in`, `_load_provider_state_with_source` and `read_credential_pool` function definitions from the two pinned source versions and executed them with synthetic in-memory stores and stubbed path/store readers. Six checks passed: absent local credentials resolve root before the change and nothing after; local credentials win in both; removing local credentials reveals root only before the change. These were isolated source-function probes, not full Hermes integration tests. Upstream's shipped tests were inspected but not executed. No real credential files were read by the probes.

## Scope depends on the credential source

Removing root `auth.json` inheritance does **not** mean that every possible credential is confined to one profile under every launch mode.

| Credential source | Verified current behavior |
| --- | --- |
| Hermes `auth.json` provider state and credential pool | Active profile only; automatic root fallback removed |
| Hermes `.env` API keys | Profile-local file; scoped API requests build a secret mapping from that profile's file and external secret sources |
| Standalone process environment | Startup loading and inherited environment are another mechanism; do not equate those with root `auth.json` inheritance |
| Hermes OpenAI Codex OAuth | Stored in Hermes auth state, deliberately separate from the Codex CLI's `~/.codex` credentials |
| Hermes Anthropic OAuth | `.anthropic_oauth.json` under the active Hermes home |
| Claude Code OAuth | Host-level `~/.claude/.credentials.json`/Keychain can still be discovered when Anthropic is explicitly configured; the shared Claude credential store remains authoritative for refresh |
| Nous Portal OAuth | Missing profile provider state fails ordinary runtime resolution; interactive login can offer explicit import from a shared Nous store. Existing Nous state still uses shared token synchronization |
| External CLI tool identities | Host tool processes ordinarily use the operating-system user's home; profiles alone are not a filesystem or CLI-account sandbox |

Source evidence: [auth store](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/auth.py), [profile secret scope](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/agent/secret_scope.py), [environment loader](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/env_loader.py), [Codex auth](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/auth_codex.py), [Anthropic credentials](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/agent/anthropic_credentials.py), [Anthropic pool seeding](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/agent/credential_pool.py), [Nous import/refresh](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/auth_nous.py).

Cloning is also different from inheritance. Static API keys can be copied into a new profile; later editing one copy does not update the other. Clone hygiene strips the single-use OAuth grants for **Anthropic, OpenAI Codex and xAI OAuth**, so these need their own sign-in. The broad docs heading about OAuth should not be read as proof that all providers have identical token-copy semantics: the implementation explicitly enumerates those three providers. [Clone implementation](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/profiles.py), [OAuth grant stripping](https://github.com/NousResearch/hermes-agent/blob/58c6f6fa201c7e3a5a54c6af70031190db01b8ef/hermes_cli/auth_oauth_grants.py).

## What Wing's two locations actually do

`AdministrationRepository.sharedProviders()` discovers canonical `default` and returns `profile(default)`. The Server entry opens `AdminProvidersPage(profile: root, shared: true)`. The Profile entry opens the same page for the selected profile. Consequently, selecting `default` under Profile reaches the same owner as Server → Providers; Server is not a second independent credential store. [Repository](../../lib/core/services/administration_repository.dart), [navigation](../../lib/core/screens/administration/administration_content.dart), [provider page](../../lib/core/screens/administration/admin_providers_page.dart).

The page's provider-selection list indicates which profiles select a **provider ID**, not proof that those profiles use the same account or key. Profile model defaults are a distinct setting. The design handoff labels the default profile's credentials as shared server providers and named-profile credentials as overrides; that assumption needs revisiting against the deployed version and the upstream change. [Provider page](../../lib/core/screens/administration/admin_providers_page.dart), [ownership handoff](../design/2026-09-14-administration-handoff.md).

The inspected stock API also limits what Wing can honestly infer:

- `GET /api/env?profile=...` reads that profile's `.env` on disk. A missing key there does not prove that every credential source is unavailable. It is not an effective account-ownership report.
- Environment mutations and OAuth operations accept explicit profile scope. The same generic API called with `default` is what the Server provider page uses.
- OAuth status source labels can describe authentication mode/source without identifying the owning profile/account.
- Older `clear_provider_auth` removes the selected profile's state and pool; it is not a global revocation. On the older fallback implementation, root credentials may become visible again afterward.
- The inspected `/api/credentials/pool` routes do not expose profile selection or install a profile scope. Wing therefore cannot treat them as arbitrary-profile account-management APIs.

These are verified against the local September 15 backend reference, not asserted to be unchanged on every later upstream commit. [Environment API](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/web_routers/config_env.py), [OAuth API](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/web_routers/oauth.py), [pool API](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/web_routers/ops.py), [credential clearing](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/auth.py).

## Decisions this evidence supports

1. Explain per-profile provider accounts as a real Hermes capability.
2. Explain the two Wing entries as two routes into profile configuration, with Server hard-wired to `default`.
3. Do not describe every root API/service key as automatically shared, even on the older backend.
4. Do not promise that a profile is using a shared account from a provider-name match or an empty `.env` alone.
5. Confirm the deployed commit before attributing either old or new inheritance behavior to this installation. A release/version label alone may be insufficient if the installation follows Git main.
6. Any UI correction must use the user's existing vanilla Hermes APIs. This investigation does not authorize or require a backend patch or upgrade.

Still unknown: the running server's exact build; its profiles' actual configured credential sources; whether the user intentionally shares external CLI credentials; and whether the deployed stock API can expose a complete, trustworthy account-owner report. This note does not propose a compatibility layer or silently preserve older behavior.
