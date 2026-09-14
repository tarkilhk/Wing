# Local provider storage observation

Read-only structural check on 14 September 2026 after the owner reported using many profiles with a single provider sign-in. This examines the local Windows installation, not all remote Hermes connections. It does not test live authentication or run OAuth/status routines that may refresh credentials.

Inspected only auth-store existence, provider identifiers and credential-pool entry counts. Credential values were not printed, persisted in this report or sent to another system. No auth-store writes, sign-ins, refreshes or disconnects were performed.

Root inspected: `C:/Users/rober/AppData/Local/hermes`, the Windows platform default returned by the installed `hermes_constants.py`. Named profiles are under its `profiles` directory; internal dot directories were excluded.

| Scope | Auth store exists | Provider-state identifiers | Pool entry counts |
| --- | --- | --- | --- |
| Root | Yes | `openai-codex` | `openai-codex`: 1; `copilot`: 1 |
| `android-qa-a` | Yes | None | `copilot`: 0 |
| `android-qa-b` | No | None | None |
| `bot2` | No | None | None |

An external Codex auth file exists; its contents were not read. A credential-pool row does not establish a currently signed-in provider, a valid credential, a separate manual login or actual model use. In particular, the Copilot pool row is not evidence that the owner manually connected a second provider.

The installed auth resolver explicitly reads provider state from the profile first, then the global root, and similarly inherits the root provider pool when the profile has no entries for that provider. Thus the observed profiles have no independent Hermes Codex provider state/pool shadowing the root entry and can use the shared sign-in. This matches the owner's description; it does not prove runtime validity on every server.

Primary sources: [provider-state source resolution](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:773>), [credential-pool fallback](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:893>), [Windows default home](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_constants.py:45>). The independent [source recheck](PROVIDER_CREDENTIAL_SOURCE_RECHECK_2026-09-14.md) covers write/disconnect semantics and design implications.

Design correction: put shared provider accounts under Server. Profile shows effective inherited access and its provider/model choices, with explicit optional profile-specific credential overrides. A supported profile parameter is not proof that the effective credential is owned by that profile. Keep provider source and the target of an action visible. Shared-account management and per-profile model selection are separate concepts.
