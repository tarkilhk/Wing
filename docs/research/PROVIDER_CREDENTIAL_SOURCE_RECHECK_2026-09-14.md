# Provider credential ownership recheck

Date: 2026-09-14. Source: installed official Hermes commit `e16f686706b1e0d5334fd1ae82190058d2a19694`. This note inspects source code only. It does not inspect live credentials, contact providers, or change backend state.

## Finding

One provider login serving many profiles is an intended Hermes configuration. The earlier design claim that provider accounts belong mostly under Profile was too broad. Account storage and a profile's choice of provider/model are separate concerns.

Hermes reads a provider's OAuth state from the selected Hermes home first, then from the shared root `auth.json` when no local provider state exists. Credential pools follow the same per-provider inheritance rule: any nonempty local pool shadows the root pool; a profile with no entries inherits root entries. This is explicit behavior, not an inference from a `profile` query parameter. See [provider state lookup](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:773>) and [credential pool lookup](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:893>).

The global fallback path is the Hermes root outside a named profile, and is absent when the current home is already the root. See [fallback path](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:485>) and [root resolution](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_constants.py:165>).

## What is profile-specific

Model and provider selection are stored in each profile's `config.yaml`. Fresh profiles copy the active profile's model block, so several profiles choosing the same provider does not imply several logins. See [profile model read and initial copy](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/profiles.py:494>) and [scoped model info](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/models.py:53>).

Profile-specific accounts are supported too. Dashboard OAuth login captures the requested profile in its session and saves Codex tokens inside that profile scope. The save writes to the current scoped Hermes auth store. See [OAuth session identity](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/oauth.py:88>), [captured scope at save](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/oauth.py:217>) and [Codex token save](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth_codex.py:145>).

An omitted or `current` profile means the dashboard process home, not a shared-server aggregate and not the phone's selected profile. Explicit named profiles resolve to their own home. Therefore a Server account editor must target the verified root identity explicitly; omitting `profile` is insufficient. See [OAuth profile normalization](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_server_oauth.py:173>) and [config profile scope](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_server_profiles.py:232>).

## Disconnect and external account caveats

The OAuth DELETE route runs inside the requested profile scope. For most Hermes-managed OAuth providers it calls `clear_provider_auth`, which removes provider state and pool entries only from the current auth store. It does not remove shared fallback credentials. A profile-only disconnect can therefore return no change for an inherited account, or remove a local override and expose the shared account again. The UI must describe the affected account source and verify the resulting state. See [disconnect route](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/oauth.py:618>) and [local auth clearing](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:1212>).

External CLI providers have distinct ownership. The route refuses automatic deletion of credentials owned by another CLI, with a special case for Hermes-owned Anthropic credentials. Environment-backed keys are directed to the key editor. See [disconnect ownership checks](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/oauth.py:531>) and [Anthropic clearing](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/oauth.py:599>).

For OpenAI Codex specifically, ordinary Hermes operation reads its own auth store, including root inheritance. It can import valid credentials from the external Codex CLI store during an offered login path or recover from some invalid-token conditions. The external store read does not itself write that file, while recovery adopts tokens into Hermes's current store. It is inaccurate to label all Hermes Codex accounts as live external Codex accounts. See [Hermes Codex read](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth_codex.py:84>), [external import](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth_codex.py:386>), [recovery adoption](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth_codex.py:168>) and [login import offer](<C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth_codex.py:660>).

## Proposed design correction

- Server gets a Providers entry for shared provider accounts, their connection status and owner-appropriate management. Root-backed accounts should say they are shared with profiles that use them. Externally managed accounts identify that source.
- Profile keeps default provider/model, auxiliary model choices and a compact account-source summary such as "Uses shared OpenAI Codex account". A profile-specific account override belongs here when supported.
- A shared account reached from Profile opens its owning Server account detail. Account management should not appear duplicated inside every profile.
- Actions name their real effect, such as removing a profile override or disconnecting a shared account. Shared changes need to state that other inheriting profiles may be affected. Removing an override must not promise that provider access ends.
- MCP configuration remains profile-owned. Moving shared provider accounts does not move the whole existing "Accounts and connectors" category to Server.

These are design recommendations from the verified inheritance behavior. They do not change approved scope or claim that the current API exposes complete credential provenance or an affected-profile inventory. A credential-pool entry is persisted state, not proof of a current usable login; authentication may be expired or unavailable. The parent task is separately recording sanitized local storage structure to establish which inheritance case applies to this installation. Local findings do not establish the account layout of every remote connection the user has.
