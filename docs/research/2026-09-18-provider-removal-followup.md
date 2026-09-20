# Exact Claude credential removal: stock Hermes follow-up

Researched 2026-09-18 against upstream commit [`0a8d4caef4650320b31f9c17a906293e680be5df`](https://github.com/NousResearch/hermes-agent/commit/0a8d4caef4650320b31f9c17a906293e680be5df). The parent research task rechecked current upstream and found this commit unchanged. This is source research and isolated fake-data execution only: no real credentials were read, changed, renewed or deleted, and no app/backend implementation changed.

## Answer

**There is a stock remote operation that can delete a Claude credential file: the managed-files DELETE API.** It works only when the real file is inside the server's permitted file scope and filesystem permissions allow deletion. It deletes the entire shared credential file, rather than one profile's access or the provider-side token. The earlier research's blanket “manual deletion only” conclusion was incomplete.

**Removing the Claude pool entry is not a reliable way to disconnect the profile.** It suppresses pool re-creation, but a stock runtime fallback can still read and renew the same Claude credential file. The UI must not promise “Stop using this account” on the strength of pool removal.

**The screenshot alone does not establish the exact physical credential file.** Hermes prints the fixed label `~/.claude/.credentials.json` even when the reader uses `CLAUDE_CONFIG_DIR` or macOS Keychain. Wing must establish the real store before offering an automatic exact-file deletion. These are independent of renewal targeting: the credential pool can identify the logical Claude source without revealing its physical authority.

Sources: [file DELETE](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/files.py#L578-L599), [file policy](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_files.py#L124-L178), [Claude status label](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_oauth.py#L76-L85), [actual credential authority selection](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/anthropic_credentials.py#L230-L256), [runtime fallback](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/anthropic_credentials.py#L523-L541).

## What each removal operation actually does

| Operation | Claude Code result |
| --- | --- |
| Profile-scoped `DELETE /api/providers/oauth/claude-code` | Rejected because this catalog provider is externally managed. This route cannot remove Claude Code's shared login. |
| Profile-scoped console `auth remove anthropic <entry-id>` | Removes that pool row and stores suppression for source `claude_code`; deliberately retains Claude Code's file. The row does not re-seed, but the fallback resolver can still use the file. |
| `DELETE /api/credentials/pool/anthropic/{index}` | Same removal registry and suppression semantics. This REST route is not profile-scoped in the inspected version and targets a positional index; it is unsuitable for a named-profile exact-source action. |
| Console `auth logout anthropic` | Clears provider/pool state in Hermes' auth store and may reset configured provider. It does not delete the shared Claude file or create source suppression. This is broader than deleting one credential and can be re-discovered later. |
| `DELETE /api/files` with the actual credential path | Unlinks that entire file if server scope and OS permissions allow it. Does not touch macOS Keychain, other credential copies, other login authorities or provider-side revocation. |
| External Claude logout or explicitly removing its actual stores | Needed for shared stores inaccessible through Hermes' file API, including Keychain. Structured Hermes Console is not an arbitrary shell and cannot run `rm`, `security`, or `claude` commands. |

Sources: [OAuth rejection and route](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/oauth.py#L519-L644), [CLI removal dispatch](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth_commands.py#L496-L522), [Claude suppression-only contract](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_sources.py#L182-L215), [REST pool removal](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/ops.py#L387-L436), [clear auth state](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth.py#L1077-L1098), [logout](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth.py#L2150-L2185), [curated console command surface](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/console_engine.py#L268-L415).

## Why pool suppression cannot mean disconnect

The removal handler deletes the row and stores `(anthropic, claude_code)` in the profile's `suppressed_sources`. `_Seeder.upsert` consults this suppression, so it does prevent the next pool load from recreating that row. However, `resolve_anthropic_token` separately falls back from the owned pool to `_resolve_claude_code_token_from_credentials(read_claude_code_credentials())`. That file resolver neither checks suppression nor depends on a pooled row: it returns a still-valid token, or attempts renewal of an expired token. The runtime resolution ladder reaches `_anthropic_env_runtime` after an empty pool, and this invokes that resolver. The OAuth catalog also directly reads the source, so its status card remains present after suppression.

This is an observed source-level gap in stock Hermes, not merely an unverified concern. Do not simulate disconnection by hiding the catalog card in Wing. Do not change other profile/provider configuration as an implicit substitute for deleting the requested credential.

Sources: [suppression storage](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/auth.py#L882-L918), [seeding suppression](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L2118-L2134), [direct file resolution and refresh](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/anthropic_credentials.py#L443-L541), [runtime pool/fallback order](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/runtime_provider.py#L895-L920), [Anthropic fallback implementation](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/runtime_provider.py#L723-L736).

## The supported file operation and its limits

The request is `DELETE /api/files` with JSON body:

```json
{"path":"~/.claude/.credentials.json","recursive":false}
```

That example is appropriate only after establishing that this is the actual store. `path` is required; `recursive` defaults to false. `~` is expanded on the server, hidden path components are accepted, and paths are canonicalized. The route deletes the target file with `unlink`; it does not edit just the `claudeAiOauth` member or delete the surrounding `.claude` directory. Wing must use ordinary dashboard authorization and accept failures from the existing policy. It must not widen the managed root, bypass containment, change permissions, or attempt another filesystem surface to get around a denial.

On a normal host without a forced root, managed files default to the server user's home and have no locked root. `HERMES_DASHBOARD_FILES_ROOT` locks all paths to that root; a hosted install whose Hermes root is `/opt/data` also locks to `/opt/data`. A file outside that root receives 403, including a symlink resolving outside. A locked root containing the true credential file permits deletion subject to OS permissions. The sensitive-file list is explicitly a read/list/download policy; this deletion handler uses its write/containment checks. No credential-file contents need to pass through Wing just to delete an established path.

`GET /api/files` returns the resolved directory path, `root`, `locked_root`, `can_change_path` and file entry metadata. This can establish file presence and scope without reading token contents, but **presence is not proof that this is the credential the status card observed**. The fixed catalog source label omits both an effective `CLAUDE_CONFIG_DIR` path and which of file/Keychain won authority selection. A custom-path or Keychain case needs additional trusted source information or a guided external action; guessing the default path is insufficient.

Deleting the file removes saved local access/refresh credentials for everyone sharing it. It is not remote token revocation or an immediate termination of already-running clients. A separate Keychain record or independently saved credential can remain, and another tool can recreate its own credential file. Re-read the stock catalog after deletion and report the observed outcome; do not unconditionally report every Claude connection disconnected. File-backed borrowed rows are pruned on future pool loads when their backing source is gone, but that does not revoke an already-issued token.

Sources: [request model](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_models.py#L87-L89), [DELETE implementation](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/files.py#L578-L599), [policy/path handling](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_server_files.py#L124-L178), [read-only sensitive guard scope](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/files.py#L92-L104), [metadata listing](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/hermes_cli/web_routers/files.py#L360-L379), [authority selection](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/anthropic_credentials.py#L230-L256), [pruning absent file-backed sources](https://github.com/NousResearch/hermes-agent/blob/0a8d4caef4650320b31f9c17a906293e680be5df/agent/credential_pool.py#L2507-L2530).

## Verification performed

An isolated Python harness AST-extracted the exact pinned `_resolve_managed_path`, `delete_managed_file`, `resolve_anthropic_token` and direct Claude file resolver implementations. All filesystem operations used temporary fake files under `/tmp`; home expansion was replaced with a fixture path, and all token readers, validity checks and refresh calls were fake. No network calls or real account material were involved. Five assertions passed:

1. Default unlocked policy accepts `~` and hidden file paths; deletes only the fake credential file and leaves its sibling intact.
2. A locked root excluding the fake credential rejects with 403 and leaves the file intact.
3. A locked root containing the fake credential permits the same deletion.
4. With an empty/suppressed pool, the production resolver still returns the valid fake Claude file token.
5. With an empty/suppressed pool and expired fake credentials, the production resolver still calls the mocked renewal and returns its fake result.

Harness location during research: `/tmp/wing-provider-design/verify_removal_sources.py`. This validates handler/path and resolver behavior, not live HTTP authentication, a deployed server's policy, a real credential's physical source or immediate effects on running sessions.

## UX consequence

Keep **Delete saved credentials** as a real conditional capability, with explicit shared-server scope. For a verified accessible Claude file, the confirmation can say: “Delete the saved Claude Code credentials on this server? Other profiles and Claude Code using this login will also lose the saved credentials.” After execution, show the rechecked state.

Do not offer a deceptively stronger **Remove from this profile** action based only on pool suppression. For an inaccessible or unidentified external store, show precise removal guidance and explain the relevant storage limitation. Other providers should use their supported provider/key removal endpoint rather than be forced through Claude's file treatment. This follow-up establishes feasibility and boundaries; the user's deployed physical source and file policy were not inspected.
