# Captured capabilities ownership

The Skills and tools route owns one `ProfileCapabilitiesSession`, created by a
required factory. The session borrows one captured `ProfileGateway`; closing the
route revokes its command authority and never closes the shared gateway. The view
owns tab selection, query text, expansion, confirmation presentation and navigation.
It submits the selected tab as an explicit command input. The state's kind labels
the observation/request, rather than owning a second selected-tab preference.

A single idle/confirming/saving operation phase reserves command admission before
opening confirmation; progress is shown only after consent, during saving.

The session owns list decoding, readiness grouping/order, generations, toggle
admission, confirmation eligibility, fresh membership, scoped dispatch,
acknowledgements, follow-up reads and instruction validation. Observations and
nested tool lists are detached immutable values. Malformed reads retain previous
rows as history and revoke toggle admission until a valid read. An uncertain
toggle likewise requires a successful explicit refresh before another command;
refresh never repeats a mutation. A confirmed acknowledgement updates the retained
row immediately. Failed follow-up reads keep that confirmation and report the read
failure separately. Enabling and configured readiness remain independent facts.

The existing gateway gains `putOwned` beside `postOwned`, using the existing owned
HTTP dispatch seam. There is no substitution through generic PUT when the adapter
lacks that capability. Both membership completion and authentication completion
must still permit physical dispatch. An already dispatched request can settle
after route retirement; it cannot publish into the retired route. Notification
storage disposal waits only for an active synchronous listener notification to
unwind, while command authority is revoked immediately.

## Current stock contract

Official NousResearch/hermes-agent main was read at
[`1298c8e74baa73e1a2b90124228d017261ac6bc4`](https://github.com/NousResearch/hermes-agent/commit/1298c8e74baa73e1a2b90124228d017261ac6bc4),
committed 4 October 2026 at 12:23:37 UTC. Inspected sources:
`hermes_cli/web_routers/skills.py`, `hermes_cli/web_routers/tools.py`,
`hermes_cli/web_models.py`, and `tools/skills_tool.py`. Private captured sources and
hash provenance are in `/tmp/wing-capabilities-upstream-1298c8e`.

- GET `skills` and `tools/toolsets` return arrays; the existing dashboard adapter
  wraps non-map JSON in `data`. Toolset rows distinguish enabled/configured/platform
  and returned tools. Skill rows carry enabled state and provenance.
- PUT `skills/toggle` accepts name/enabled and acknowledges ok/name/enabled.
  PUT `tools/toolsets/{name}` acknowledges ok/name/platform/enabled and nullable
  `post_setup_started`. Install-on-enable is best effort, not a completed setup.
- GET `skills/content` returns name/content/path. The server reads UTF-8 with BOM
  stripping; the viewer displays the actual returned content.

All these requests use the captured canonical profile. Stock acknowledgements do
not echo profile and provide no CAS/version or idempotency token. Membership checks
and dispatch fencing cannot prevent another client changing configuration after
preflight. A valid reread establishes observed current state, not proof of which
earlier request produced it. This route has no durable journal or second cache.

## Verification scope

The existing four screen interaction cases retain captured-profile writes,
rejection, tab/read races, setup consent, search and instructions. Focused session
cases cover detached immutable history, malformed-read admission, retirement while
membership/authentication waits, acknowledgement retained after failed read,
contradictory acknowledgement followed by read-only recovery, and synchronous
listener retirement before confirmation. Their execution is pending parent-run
acceptance; source authoring and formatting alone are not passing evidence.

Physical admission, ACK/read separation and delayed lifetime sequences require
behavioral tests; an import rule cannot establish them. The completed-view raw
adapter dependency property can be enforced by the existing parsed import graph
mechanism. Tool setup/provider/model selection and skill library/Hub workflows stay
explicitly separate remaining migrations.
