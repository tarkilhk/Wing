# ADR 0001: Use explicit request-scoped Hermes profiles

- Status: Accepted
- Date: 2026-09-06

Current qualification, 2026-09-15: the ownership decision remains accepted. The later [product scope](../PRODUCT_PLAN.md) supersedes this record's legacy-server fallback: the active workspace requires modern profile-aware contracts and fails visibly when they are unavailable. The context below describes the original decision baseline.

## Context

Hermes Android currently binds its active Workspace to one `SavedConnection`. Its legacy “Switch profile” UI actually switches saved Android connections. Official Hermes profiles are different: each profile identifies an isolated `HERMES_HOME` with its own sessions, projects, configuration, and state.

A profile-aware Hermes dashboard already supports profile discovery and explicit profile scope on session REST routes and session/project JSON-RPC methods. `POST /api/profiles/active` changes a sticky default for later launches; it does not retarget an already-running client.

## Decision

Model connection and profile separately:

```text
WorkspaceScope = SavedConnection identity + canonical Hermes profile name
```

Use one authenticated dashboard connection and include the canonical profile in every profile-owned request. Selecting a profile reconstructs and reloads foreground Workspace clients and state for that scope.

Modern profile mode fails closed if an operation lacks a valid profile. Older servers remain on an explicit legacy path rather than pretending to support profile selection.

## Consequences

### Positive

- Matches the dashboard's supported remote request-scoping model.
- Avoids mutating host-wide sticky defaults.
- Prevents cross-profile reads and writes.
- Does not require Android to reproduce Electron process orchestration or infer ports.
- Keeps host connection/authentication configuration distinct from workspace identity.

### Negative

- Every profile-owned API surface, cache, and test must carry scope.
- Partial server capabilities need visible compatibility behavior.
- Existing connection-only caches cannot be safely reused.

## Rejected alternatives

### Use `POST /api/profiles/active`

Rejected because it changes future-launch defaults and does not safely switch a live Android Workspace.

### Treat every profile as a saved connection

Rejected because it duplicates host/auth configuration, cannot discover host profiles cleanly, and preserves the misleading legacy model.

### Omit profile when routing fails

Rejected because the server may then target its own current/default profile, risking cross-profile writes.

### Reproduce Electron's local gateway pool

Rejected as the baseline because Android is a remote client and the dashboard already exposes an authenticated request-scoped contract.
