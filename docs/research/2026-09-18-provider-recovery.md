# Provider recovery capabilities in stock Hermes

Researched 2026-09-18 for Wing's provider-account recovery design. Source inspection only: no account operations, credential access, server commands, or backend/application changes. Target: upstream main commit [`0a8d4caef4650320b31f9c17a906293e680be5df`](https://github.com/NousResearch/hermes-agent/commit/0a8d4caef4650320b31f9c17a906293e680be5df), fetched today. The stock source below, not a deployed server's age, defines the design target.

**Follow-up completed:** upstream main rechecked at the same commit. Automatic Claude-source renewal matching was exercised with synthetic credentials using the actual upstream listing, target resolution, source upsert and refresh-dispatch functions. It is feasible for the normal, uniquely identified Claude Code source; an obligatory user credential picker is unnecessary. Actual deletion is also possible through the stock file API when its file policy permits the verified source path. Removing a pool entry is not a reliable disconnect. See the focused findings below and the [removal follow-up](2026-09-18-provider-removal-followup.md). No real account or server mutation was performed.

## Recovery is possible, but capabilities differ

| User action | Verified stock capability | Design implication |
| --- | --- | --- |
| Check status | Profile-scoped OAuth catalog reports source, expiry, stored refresh-token presence and disconnect metadata. | A status reread is not a token renewal or successful model request. |
| Renew a token | Structured console supports `auth refresh <provider> [target]` for Anthropic, Nous, OpenAI Codex and xAI OAuth, subject to entry/source checks. | A real **Try to renew** action is feasible, but only with correct credential targeting and console transport. |
| Sign in again | Catalog supplies device-code flows for supported providers; external providers supply CLI instructions. | Device-code providers can use their stock flow; external providers need an external sign-in guide. |
| Remove Hermes-managed OAuth | Profile-scoped OAuth DELETE, gated by `disconnectable` and source. | Describe local removal, not provider-wide revocation. |
| Replace/remove a stored API key | Profile-scoped PUT/DELETE `/api/env`. | Bind to the actual variable, not merely provider name. |
| Delete shared Claude Code login | OAuth DELETE rejects this external source, but stock file DELETE can remove a verified credential file within the permitted file root. | Offer confirmed server-wide file removal when source/path is established; otherwise explain the missing source information or file-access restriction. Keychain credentials need separate handling. |

Sources: [OAuth routes](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/oauth.py#L519-L644), [catalog](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_oauth.py#L124-L168), [refresh handler](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth_commands.py#L542-L594), [env routes](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/config_env.py#L725-L740).

## The console can renew credentials but cannot run a generic terminal

`/api/console` exchanges structured JSON frames and runs the curated `HermesConsoleEngine` in-process. It never spawns a shell or PTY. The engine rejects shell syntax and unregistered commands; therefore `claude setup-token`, `rm`, and arbitrary external CLI operations are unavailable there. `auth refresh`, `auth remove`, `auth add`, and `auth logout` are registered mutating Hermes commands. [Console engine](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/console_engine.py#L268-L415), [socket route](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/chat_ws.py#L154-L170).

The socket accepts a `profile` query parameter, validates it and executes each command inside `_profile_scope(profile)`. Client sends `input`/`command`; mutating commands return `confirm_required`; a matching `confirm` frame then executes. Completion is structured (`ok`, `error`, `timeout`, `cancelled`), with human-readable output/error text. There is a 60-second command deadline. Running commands cannot receive another input command. Command output is captured until completion, so this is not an interactive browser-login terminal even when an interactive CLI handler is registered. [Protocol and scoping](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/chat_ws.py#L190-L415), [output capture](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/console_engine.py#L51-L80).

Authentication must follow the current dashboard mode: gated dashboards use short-lived, single-use tickets; their session token alone is rejected. Non-gated mode uses the dashboard session token. Host/origin and peer gates also apply. A generic bearer header is not this websocket's authentication contract. [Websocket auth](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_chat.py#L165-L290).

### Renewal eligibility and targeting

The refresh command requires an OAuth pool entry with a refresh token and provider membership in the explicit refreshable set: `anthropic`, `nous`, `openai-codex`, `xai-oauth`. Nous additionally requires source `device_code`. Other providers can have a refresh token without being supported by this command. Omitted target is accepted only when the pool contains exactly one entry; otherwise the server requires index, stable entry ID, or exact label. [Eligibility](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth_commands.py#L542-L594), [supported set](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L679-L692).

| Pool provider | Refresh constraint beyond OAuth + stored refresh token |
| --- | --- |
| `anthropic` | Supports borrowed `claude_code` and Hermes-managed sources; borrowed renewal updates a shared credential authority. |
| `nous` | Only source `device_code`; other OAuth entries are rejected. |
| `openai-codex` | Uses Codex refresh implementation. |
| `xai-oauth` | Uses xAI refresh implementation. |
| All other providers | This command rejects renewal, even if status advertises a refresh token. |

For the screenshot's `claude-code` catalog card, the pool provider is **`anthropic`**, source **`claude_code`**. Its refresh is supported and writes back to the shared Claude credential authority under a cross-process lock. This can affect every profile borrowing that login. Successful renewal proves the grant can be renewed, not that quota is available. A successful command can also merely adopt another process's tokens while retaining a non-OK status; always reread account/pool state instead of translating `complete: ok` into “connection healthy.” [Shared-source refresh](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L1172-L1212), [write-back](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L1286-L1396).

**Targeting limitation:** the OAuth catalog does not expose pool entry IDs. `/api/credentials/pool` exposes them but has no profile parameter/scoping in this commit. Profile-scoped console `auth list <provider>` prints stable IDs and sources, but only in a human-readable table, with no JSON flag in the parser. Wing must not use an unscoped pool result to mutate another selected profile. Exact entry discovery/matching needs a focused implementation validation; a hidden command with guessed provider/index is not an adequate design. [Pool listing](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/ops.py#L285-L331), [console list](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth_commands.py#L460-L493), [parser](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/subcommands/auth.py#L35-L59).

**Updated design assessment:** no dedicated REST renewal route was found, but the console route is a genuine stock renewal mechanism. For the standard Claude Code source, Wing can discover the matching entry automatically; requiring a user picker in the ordinary case would be unnecessary. The discovery is an adapter for the current text output, not a provider-name guess. Reject ambiguous or incomplete output, and send the discovered stable ID. A picker is only useful when there really are multiple identifiable candidates; it does not repair untrustworthy parsing.

### Exact-source matching: follow-up verification

The catalog's `_claude_code_only_status()` and Anthropic's pool seeder both call the same `read_claude_code_credentials()` function. The pool stores this as source `claude_code`. `_upsert_entry` retains the existing stable ID and deduplicates entries with that exact source. That supplies the missing connection between the visible expired credential and the renewable pool entry. Several other Anthropic credentials can coexist without making this source ambiguous. [Catalog reader](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_oauth.py#L76-L86), [upsert](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L2021-L2070), [seeder](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L2139-L2185).

The client sequence can be:

1. Capture the selected profile and observed `claude-code` / `claude_code_cli` source.
2. Run `auth list anthropic` through that profile's stock console.
3. Parse the complete current-format result; require one OAuth entry from the `claude_code` source and retain its stable ID. Validate heading/count, sequential rows and unique IDs; reject control characters, truncated output and multiple possible structural interpretations.
4. Submit `auth refresh anthropic <stable-id>` and confirm that exact command through the stock console protocol. Do not select the first entry or omit the target just because the UI has one card.
5. Re-read the catalog to establish whether the observed expiry changed. Report rejected renewal or unchanged/unavailable status honestly.

The normal source is a singleton credential authority, not an immutable token byte string: another process may rotate it while the operation is pending. Hermes re-reads that same source under its shared lock before renewal and writes the replacement pair back to it. Renewing the current sign-in at the same authority is the intended behavior. [Source locking](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L1172-L1224).

**Executed probe:** `/tmp/wing-provider-design/probe-targeting.py` extracts the pinned upstream `auth_list_command`, `auth_refresh_command`, `_display_source`, `_upsert_entry` and actual target-resolution mixin, running them with synthetic in-memory entries and a candidate strict client parser. All 12 cases passed: multi-credential source lookup; ID targeting after reordering; ID preservation and source deduplication after token rotation; absent/duplicate/display-ambiguous source rejection; multiline/structurally ambiguous label rejection; incomplete/truncated output rejection; missing target rejection; and refusal to refresh an entry without a refresh token. No real store, provider exchange, network request or production secret was used. This is a feasibility probe, not production parser or transport validation.

**Remaining boundaries:** the seeder may intentionally omit Claude credentials when the profile is not configured to use Anthropic, uses API-key-only mode, or suppresses this source. A red catalog card does not override those choices; Wing must not silently enable borrowing. `_display_source` hides a `manual:` prefix, so unusual imported/hand-edited `manual:claude_code` records are not distinguishable from the singleton by that output alone. Do not claim generic raw-source identity from every display string. The target resolver prefers exact IDs, then labels, then numeric indices; it lacks an ID-only conditional-mutation contract. Refresh targeting should therefore be revalidated immediately before submission, with no retry against a replacement entry if the target disappeared. Real websocket admission, provider exchange, concurrent source replacement and end-to-end UI results remain implementation validation.

## Removal and replacement semantics

OAuth DELETE refuses external sources except Hermes-owned Anthropic credentials; it also refuses env-backed credentials and directs users to Keys. Anthropic deletion removes Hermes' PKCE file and auth-store state, never `~/.claude/*`. Claude's `disconnect_command` is a shell instruction, not an executable HTTP operation. It uses a fixed `~/.claude/.credentials.json` path (plus macOS Keychain deletion), while the actual credential reader also honors `CLAUDE_CONFIG_DIR`; therefore do not imply that blindly copying that command necessarily clears every detected source. [Removal API and commands](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/oauth.py#L519-L644), [credential reader](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/anthropic_credentials.py#L230-L256).

Console `auth remove anthropic <entry-id>` offers a different operation: it removes the pool entry and suppresses that source in the selected profile, while retaining Claude Code's file. The OAuth catalog still directly reads the external file and does not use this suppression as its status, so this must not be presented as deleting the shared login or expected to make that catalog card disappear. **Follow-up found a concrete bypass of this suppression in ordinary runtime resolution:** after an empty pool, the Anthropic resolver can still read/use the Claude file directly. Therefore do not offer this as a reliable Disconnect action. See the [removal follow-up](2026-09-18-provider-removal-followup.md) for the isolated proof and the actual stock file-deletion route. [Removal dispatch](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth_commands.py#L496-L522), [suppression-only source](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_sources.py#L182-L215), [catalog status](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_oauth.py#L76-L86).

PUT `/api/env` writes the selected profile's env credential and reconciles value-matching config mirrors. DELETE removes that env entry, env-seeded pool mirrors and affected cache entries; independent OAuth/device-code/manual credentials remain. Reads enumerate `.env`, not arbitrary inherited process credentials. Deleting one stored key is consequently not a promise of removing all access for the provider. [Env read/write](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/config_env.py#L225-L296), [env delete](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/config_env.py#L725-L740).

## Claude sign-in guidance requires care

Hermes advertises `claude setup-token` for its external Claude Code card, but that card reads the CLI credential file/Keychain. Anthropic's current documentation explicitly says `setup-token` prints a token and does not save it; it must be supplied through `CLAUDE_CODE_OAUTH_TOKEN`. Its normal `/login` flow manages the stored CLI login; `/logout` removes it. A recovery guide must not imply merely running `setup-token` repaired the credential file. Hermes' helper also does not capture/persist the printed output: it runs the command and then rereads credentials/environment. [Catalog metadata](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_oauth.py#L159-L167), [Hermes helper](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/anthropic_credentials.py#L544-L559), [Anthropic authentication documentation](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token).

The inspected stock web `OAuthProvidersCard` copies CLI commands and labels connected external providers as managed externally; it does not execute those commands. `HermesConsoleModal` uses the structured console and suppresses input while a command is running. A source comment promising an embedded terminal is not evidence that arbitrary external commands work. [Provider card](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/web/src/components/OAuthProvidersCard.tsx#L188-L267), [console modal](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/web/src/components/HermesConsoleModal.tsx#L218-L275).

## Confidence and remaining validation

High confidence in declared routes, allowed commands, source ownership, refresh eligibility and CLI token-persistence distinction. These conclusions derive from pinned implementation and current first-party Claude documentation. No live transport/login/refresh was attempted. Before implementation, validate native dashboard-ticket websocket admission, exact profile-scoped pool-entry matching, shared-source renewal outcomes and error/cancellation rereads. Native renewal is a feasible client-only extension, not a finished transport already verified in Wing.

## Implementation verification, 18 September 2026

Rechecked upstream main at `9dda4332f80c66994fe0e21197a8065a73a88991` before
implementation. OAuth routes, console framing, refresh commands and credential
source handling used by this design were inspected against that revision.
Additional generic-provider details were verified directly in
[OAuth status cards](https://github.com/NousResearch/hermes-agent/blob/9dda4332f80c66994fe0e21197a8065a73a88991/hermes_cli/web_routers/oauth.py),
[pool-first status](https://github.com/NousResearch/hermes-agent/blob/9dda4332f80c66994fe0e21197a8065a73a88991/hermes_cli/auth_nous.py#L1267-L1303),
and [Codex's store reader](https://github.com/NousResearch/hermes-agent/blob/9dda4332f80c66994fe0e21197a8065a73a88991/hermes_cli/auth_codex.py#L84-L101).
Codex's card hardcodes `has_refresh_token=false` but its reader requires a refresh
token. Codex/xAI pool observations identify `pool:<label>`; the client must match
the reported label then keep the listed stable ID. Status helpers can select
credentials and automatically resolve/refresh them internally, so a catalog read
is not a universal guarantee of zero backend credential changes.

Implementation and remaining limitations are recorded in the
[recovery contract](../design/2026-09-18-provider-recovery.md). Validation used
synthetic metadata and console frames; no actual credentials were changed.
