# ADR 0002: Preserve running turns across profile switches

- Status: Accepted
- Date: 2026-09-06

Current qualification, 2026-09-16: the lifetime/ownership decision remains accepted. It does not guarantee process-death recovery or notification delivery. Android foreground monitoring now retains the same engine across activity destruction; process termination still requires reopening Wing. Use [background notification limits](../BACKGROUND_NOTIFICATIONS.md) and [current storage/recovery scope](../PRODUCT_PLAN.md) for those boundaries; no separate durable work database or Firebase sender is selected.

## Context

Changing the visible profile is a navigation and data-scope action. It is not an instruction to stop work. Wing already has an application-level turn controller designed to retain coordinators, sockets, and recovery authority above screen lifetimes. Official Hermes Desktop likewise permits background profile sockets and sessions to keep streaming concurrently.

Closing a profile's turn controller or invoking interrupt during a switch would conflate foreground UI ownership with agent execution ownership. It could destroy useful work and violate user expectations.

At the same time, stale list/tree responses and old-profile events must never update the newly selected profile's visible state.

## Decision

Separate foreground Workspace scope from background turn ownership.

- Foreground state is keyed by `connectionId + profileName` and protected by a switch generation.
- Running work is keyed by `connectionId + profileName + sessionId` and owned above screen/route lifetime.
- A profile switch detaches foreground listeners and invalidates stale reads only.
- It does not call `interrupt`, `closeAll`, or dispose a resource that owns unsettled turns.
- Old-profile events continue into their matching recovery journal and notification path.
- Returning to the profile/session restores the current transcript and status.

Resources may be disposed after all owned turns settle and a documented idle policy permits eviction, or following an explicit user stop/disconnect action.

## Consequences

### Positive

- Long-running work survives profile navigation.
- Results remain attributable to the correct profile and session.
- Existing durable recovery and background notification behavior is preserved.
- Users can monitor work across profiles without keeping a chat visible.

### Negative

- More than one profile-scoped client/resource set may remain alive.
- Resource eviction, reconnection, notifications, and deep links need profile-aware behavior.
- Tests must cover concurrent profile events and process restart recovery.

## Rejected alternatives

### Cancel all old-profile activity on switch

Rejected because it is destructive, unnecessary, and unlike official Desktop's concurrent background-profile behavior.

### Keep one global socket and reassign it to the new profile

Rejected because in-flight turns and events would lose stable ownership and could contaminate the new profile's UI.

### Allow events to update whichever chat is visible

Rejected because session identifiers are not sufficient without connection/profile scope and late events could render in the wrong Workspace.
