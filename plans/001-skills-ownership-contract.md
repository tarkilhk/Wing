# Skills library ownership

The installed library, Hub catalog/detail reads, provenance eligibility, content
edit baseline/draft and skill command outcomes belong to one captured
`ProfileSkillsSession` per library/Hub route. Detail, preview and editor children
borrow it. Widgets keep search text, sort controls, input controllers, dialogs,
scroll and navigation. The owner has no public adapter or mutable row escape.
This replaces policy in `admin_skills_page.dart`; it adds no persistence format,
backend changes or alternate compatibility interface.

## Current stock source

Official upstream main was verified through GitHub on 5 October 2026 at
[`af90026aa09949579bd423d24def3d38f743cde0`](https://github.com/NousResearch/hermes-agent/commit/af90026aa09949579bd423d24def3d38f743cde0).
The inspected source is retained privately under `/tmp/wing-skills-upstream-af90026`.
Relevant current sources and SHA-256 of the retained UTF-8 bytes:

| Source | SHA-256 |
| --- | --- |
| `hermes_cli/web_routers/skills.py` | `cfcc9349c8658e91bfcae35a56795afe27ff5233fbc57e571276c024ba1ef6ba` |
| `hermes_cli/web_routers/status.py` | `ee815b039c9d0fdbf88a167dc12709ff8ba164984deed7fd19a5527420fe7a9b` |
| `tools/skill_usage.py` | `abd9257f4b869749a0c9115f44c2a790a0d478787f52f4949000a443a148299c` |
| `tools/skills_tool.py` | `a7915f60749ee69df00e6ae4f24e00aa2c80b7f429d22da51a97528faa7fcbe0` |
| `tools/skill_manager_tool.py` | `af9e95f14373e5a7f14b2493c84fa606805411782d49b4218471d22d0f39b4ca` |
| `agent/learning_mutations.py` | `b48d336566edde21630e5cb92b7d8b6d5a3eff088d64915d974da12f86e9764c` |
| `hermes_cli/web_server_profiles.py` | `b12889996d9e60a1866f0d512002d025d1ec102b1be32d1f314246c74b535d85` |
| `hermes_cli/web_routers/_common.py` | `cb7785146a473da8324b43ec986c50109e51e3802ad74548c7b435f8660ef501` |

The [skills routes](https://github.com/NousResearch/hermes-agent/blob/af90026aa09949579bd423d24def3d38f743cde0/hermes_cli/web_routers/skills.py)
return installed name/description/enabled/provenance and **integer** activity
count. The inspected `activity_count` sums integer-converted counters, so a historical
map-shaped usage count is not read; the client does not invent a nonnegative
count policy that this function does not enforce. The current HTTP adapter
wraps top-level lists in `data`; the feature does not introduce another envelope.
Official/search catalog rows name identifiers; preview reports that identifier,
source/trust and exact instructions. Timed-out sources mean partial results.

GET `skills/content` reports exact requested name and UTF-8-sig text. PUT is a
full rewrite through stock validation and atomic file replacement; `success:true`
is its ACK, without a name/version receipt. It has no compare-and-swap. Fresh
content/provenance preflight cannot eliminate a concurrent server write between
that read and PUT. A leading U+FEFF draft is explicitly invalid because GET strips
it; the client never silently rewrites the user's text. Frontmatter and security
validation remain server-owned. A known finite HTTP rejection may retain the
completed fresh preflight for an explicit corrected retry; uncertain delivery
requires read-only review and never triggers automatic replay.

DELETE `learning/node` with the captured skill name archives a skill and returns
`ok:true` on acceptance. The client excludes memory IDs and requires fresh
`agent` provenance. Stock handles pinned/archive policy; it reports failures.
Hub install/uninstall/update POST ACKs identify a started action, never completion.
Per-skill names use stock's readable slug and SHA-1 suffix; update is
`skills-update`. The existing `AdministrationOperationSession` owns subsequent
polling and exact PID replacement checks. No install/update replay or invented
idempotency is added.

## Facts and transitions

| Fact | Owner and transition |
| --- | --- |
| Connection/profile | Captured private scoped adapter for the route lifetime; required factories are composed at the real parent. |
| Installed/catalog/content/preview | Strict pure codec, immutable replacement only after a successful read; malformed refresh retains history and blocks mutation. |
| Search/order | Search input and order preference remain presentation intents; catalog request selection/generations belong to the owner. A search admitted during a command is read after its settlement. |
| Instruction baseline/draft | Owner-held immutable edit observation. Same-field preflight rejects conflict, convergence sends no PUT. Newer draft edits survive an earlier ACK. |
| Child editor authority | Issued object identity. Child disposal revokes unsent dispatch while the parent stays usable; already dispatched ACK settles into the live parent. |
| Admission | Idle → confirming → saving → result review → idle; duplicate admission reserved before dialog callbacks. Saving progress begins after consent. |
| Dispatch | Fresh relevant observation and profile membership, then existing physical `ownedMutation` with captured profile in query/body and adjacent retirement callback. |
| ACK/readback | Confirmed save/archive/start remains confirmed when later reads fail; uncertainty blocks another mutation until explicit read-only review. No automatic mutation retries. |
| Resources | Route lease plus admitted operation lease; immediate retirement revokes dispatch/publication, notifier disposal waits only for synchronous notifications to unwind. Tracker is created from ACK and disposed in `finally`; result view borrows it. |

## Subtraction and prevention

Removed raw profile/row constructor surfaces, mutable view save/busy/error/baseline
bags, usage coercion, endpoint selection, provenance/action admission, conflict
checks and write/readback interpretation. Existing classes remain meaningful
presentation modules; their dialog/navigation delegate methods are not obsolete
APIs. No compatibility re-export or forwarding old constructor is retained.

A small existing declared-dependency guard can protect the completed view against
reintroducing the canonical raw administration/gateway namespace; typed session
and widget imports remain valid. Root owns the separate guard/retirement handoff.
That finite static property cannot prove ACK, asynchronous dispatch authority,
readback uncertainty or draft revision preservation. The two focused public owner
controls in `profile_skills_session_test.dart` cover held unsent child retirement
and ACK followed by unavailable readback through the actual existing adapter.
They are source-authored, not yet run; no original RED, build, behavior or Studio
render acceptance is claimed by this handoff.
