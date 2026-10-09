---
name: maintain-feature-architecture
description: Keep Wing's ownership map, contracts and file/root manifests accurate when adding features, fixing behavior, refactoring or deleting code.
---

# Maintain feature architecture

Deliver the requested change with its ownership and verification records updated
in the same commit or PR. This repository-local skill is reached through
`AGENTS.md`; agents can also read it explicitly by path. Paths below are relative
to the Wing checkout root, not this skill directory.

## Find the seam

Read the affected feature row in `docs/ARCHITECTURE.md`, its actual source and
linked contracts. Inspect relevant entries in `tools/architecture/roles.json`
and `tools/architecture/roots.json` when file roles or registrations are involved.
Identify the owner of each changed fact, commands callers use, observations views
consume, and lifetime/I/O boundaries. Resolve a stale map against source before
using it to design the change.

Extend the existing responsible owner. A new owner earns its place by hiding a
distinct workflow or lifetime behind a smaller interface. Pure policy belongs in
functions/value types; views retain presentation and forward intent. Establish
the affected interfaces before parallel implementation. Give each worker explicit
modules/files; the integrating agent reconciles shared map and manifest edits.

## Update the relevant records

| Change | Record to maintain |
| --- | --- |
| Owner, business fact, command/observation boundary or dependency direction | Affected row and interface description in `docs/ARCHITECTURE.md` |
| Production Dart file added, removed, renamed or reassigned | `tools/architecture/roles.json`: actual role, feature and containing library |
| Authored file added, removed or renamed | `tools/architecture/roots.json:files`: exact present path, area and provenance |
| Entry point, native registration, dynamic resource or direct dependency changed | Relevant `roots`/`direct_dependencies` evidence in `tools/architecture/roots.json` |
| Validation, async ordering, durability, cancellation or resource ownership changed | Existing feature contract and focused behavioral regression at that interface |
| User-visible route, behavior or prerequisite changed | Relevant user guide and existing journey/verification instructions |
| Incorrect pattern encountered | Follow `tools/agent_skills/create-regression-guards/SKILL.md`; reuse an effective check or add a focused guard |

Keep one authoritative description for each responsibility. Link existing
contracts and verification instructions; create a new feature document only when
the existing map and references cannot explain the new boundary clearly. Describe
the real user entry path, prerequisite and observable success when documenting a
journey. A broken supported behavior is a product defect, not a reason to rewrite
the guide to claim success.

The completed `plans/001-*` program and hash-bound inventories are historical
audit records. Preserve their accepted source bindings and receipts. Maintain
current ownership in `docs/ARCHITECTURE.md` and the live manifests; ordinary edits
do not require a new whole-checkout audit or refreshing every historical hash.
Put change-specific results in the PR/task report, with private captures stored
according to `docs/PERFORMANCE.md`.

Migrate affected callers together and remove the superseded implementation and
its exclusive tests/helpers/resources. Inspect the deletion closure for newly
orphaned code. Classify retained dynamic roots with concrete registration/caller
evidence. Existing compatibility and external-action authorization rules remain
in `AGENTS.md` and the user's instructions.

## Verify and hand off

Finish the active user scope before reviewing or integrating unrelated features.
For coordinated delivery, accept only a READY handoff with frozen source,
explicit file/hunk ownership, completed scoped checks and stated limits. A
progress message or passing partial run is not readiness. Reconcile shared
hunks against the published base; preserve already published contributions.
Keep unfinished work out of the tested candidate.

Use the workspace's canonical coordination record when multiple sessions share
builds or devices. Assign each emulator to one acknowledged owner. Transfer it
only after that owner has stopped its work and released the lease; queuing a
message does not establish release. Keep APK assembly under the shared build
lease. Reuse completed checks according to the verification policy below.


Include affected shared UI contracts in a feature handoff. Adding selection
controls requires `test/studio_selection_test.dart` alongside the feature tests;
it checks the Studio selection rule across production sources.

Use the applicable independent commands in `tools/architecture/README.md`.
File-set changes require `python3 tools/architecture/rules/authored_census.py`;
Dart role changes require `dart run tools/architecture/rules/role_inventory.dart`;
executable Dart root changes require
`dart run tools/architecture/rules/dart_main_roots.dart`.
Choose behavior checks, integration scope and failure recovery using
[verification scope and stopping](../../../docs/TESTING.md#verification-scope-and-stopping).
Done when the planned affected checks and required gates are accounted for with
their evidence or stated limits.

Review the actual diff against the affected map row, interfaces and registrations.
For a new or moved boundary, a reviewer should be able to locate its owner,
callers and regression check from the map and source. Static manifests establish
coverage, not truth of prose or runtime liveness; those claims need source review
and relevant behavioral evidence.

Finish with the changed responsibility, obsolete code removed, records updated
(or why their existing description still applies), checks run and remaining
limitations. Documentation maintenance is complete when the affected records
describe the delivered source; a larger inventory or test count is not the goal.
