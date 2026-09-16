# Administration experience: approved direction

Status: IMPLEMENTED AND VERIFIED — see Plan 003 for acceptance evidence.

On 17 September 2026, the owner accepted all ten recommendations from the
administration design review and requested documents and a goal definition
while two other agents finish their work. Preparation is authorized now;
implementation and goal activation were subsequently authorized in an isolated
branch. The owner explicitly permits redesigning incoming feature UI to achieve
Studio consistency, while retaining its functionality.

The owner explicitly confirmed that **Profile / Server / Health stays**.
Recommendation 3 explains ownership within and between those tabs; it does not
replace the navigation split.

This document owns the accepted design requirements. The
[implementation plan and goal](../../plans/003-administration-experience.md)
own execution order and completion evidence. The [Studio charter](../DESIGN_SYSTEM.md)
and [ownership contract](2026-09-14-administration-handoff.md) remain the shared
references. The implementation plan records delivered behavior and verification evidence.

## Outcome and design thesis

Administration becomes a compact, informative workspace for shaping an agent.
On entry, a person can identify the server and profile, understand the current
configuration, find known issues, and reach the correct editor. Deeper pages
explain choices and effects while retaining truthful state and scoped writes.

The signature is a small **profile brief** followed by navigation rows that show
current values. Use Studio's existing Roboto typography, grouped rows, opaque
panels, small rectangular controls, and selected accent. Spend visual emphasis
on useful information and exceptions rather than a large hero or decoration.

## Accepted requirements

Requirement IDs correspond to the ten accepted review recommendations. Every
sub-item is in scope; prioritization in the plan changes order, not inclusion.

### R1. Profile brief and informative navigation

- R1a: Replace the oversized form-like profile selector with a compact identity
  treatment: display name, one-line description when available, and an explicit
  change-profile action. Keep the selected server visible across all three tabs.
- R1b: Profile rows show real current configuration: model/reasoning, identity
  description, memory retention and character budget, behavior, skills/tool
  enablement and known setup issues, effective access/connectors, and scheduled
  tasks' next run and latest known outcome. Select the most useful concise facts;
  details remain available in the owning screen.
- R1c: Group Profile into Agent setup (Models and reasoning, Identity, Memory,
  Behavior) and Capabilities and automation (Skills and tools, Access and
  connectors, Scheduled tasks). Defaults may be relabeled Models and reasoning;
  retain helper assignments, speed and fallback-model operations inside it.
- R1d: Summaries load independently, retain last confirmed observations with
  freshness information, and never turn missing/failed data into zero or off.
  Opening the overview must not trigger inference, installation, connector tests,
  Doctor, or other operational actions.

Illustrative structure; brackets are placeholders, never production facts:

```text
Administration
● Home server
[Search settings]
Profile               Server               Health

Personal                                   Change
Research, planning and everyday questions

Agent setup
Models and reasoning                            ›
[Current model] · [Supported reasoning setting]
Identity                                        ›
[Profile description]
Memory                                          ›
[Retention setting] · [Budget in characters]
Behavior                                        ›
[Approval mode] · [Compression setting]

Capabilities and automation
Skills and tools                                ›
[Enabled skills] · [Known setup issue]
Access and connectors                           ›
[Confirmed access source] · [Connector facts]
Scheduled tasks                                 ›
[Next task and run time] · [Latest known outcome]
```

### R2. Deliberate Studio hierarchy

- R2a: Reduce header/selector overhead, strengthen row titles, quiet metadata,
  and align trailing controls/statuses. Use meaningful groups and thin separators.
  Keep important content near the top without fixed-height text clipping.
- R2b: Consume shared tokens in light/dark and all five accent families. Roboto,
  16 dp gutters, 4 dp spacing grid, 6 dp action corners, 8 dp group corners,
  24–28 sp titles, 16 sp body and 12–13 sp metadata follow the charter.
- R2c: Give exceptions concise status labels and relevant actions. Keep semantic
  warning/error colors separate from the chosen accent. Selected controls use
  background tint without ticks, radio dots or selected-only borders.

### R3. Ownership and consequences, with the three tabs retained

- R3a: Profile model/access details identify the established credential source:
  shared server account, profile-owned credentials, external management, or
  unavailable provenance. Shared-account links open their Server-owned detail.
- R3b: Server provider detail clearly identifies shared ownership. Profile
  overrides remain in Profile; MCP configuration stays profile-owned. Selecting
  a provider does not prove use of a particular shared account by that profile.
- R3c: Explain effect beside the decision before submission: new-chat defaults,
  profile configuration, or process-wide runtime changes as appropriate. Keep
  the captured server/profile editing target visible and fixed.
- R3d: Connection LED, stored credentials, cached runtime observations and model
  readiness communicate distinct facts. Health findings link to the single
  owning editor instead of duplicating forms.

### R4. Findings-led Health and complete recovery journeys

- R4a: Give selected-profile and runtime observations distinct compact sections.
  Within each, show check coverage, freshness and actionable findings before
  diagnostic utilities. Before checks, show Not checked; partial coverage remains
  explicit. Server/runtime controls remain reachable without a selected profile.
- R4b: Each actionable finding identifies the affected owner and offers a
  specific recovery action. Keep Logs, Doctor and Security audit accessible.
- R4c: Preserve the finding and navigation context while visiting its editor;
  return to the same finding and offer recheck. Only safe observation reads may
  refresh automatically; operational diagnostics remain explicit actions.
- R4d: Diagnostic results lead with the verified outcome and supported next
  action, with selectable raw output in a disclosure. Raw unstructured results
  must not become invented structured diagnoses or a blanket healthy verdict.

### R5. Scannable provider inventory

- R5a: Replace large repeated provider cards with compact comparable rows:
  provider name, precise status, known source/expiry and a disclosure. Make
  renewal immediately reachable for actionable expired sign-ins.
- R5b: Put detailed provenance, token/renewal information and removal controls
  in provider detail. Keep external ownership and removal consequences clear.
- R5c: Provide an explicit Add service key action using the supported service
  catalog; addition must not depend on discovering search. Keep search/filtering
  useful, and never retrieve secret values merely to display an inventory.
- R5d: Profile access emphasizes effective access/source; Server emphasizes
  shared accounts. Do not invent account-to-profile impact inventories.

### R6. Capabilities organized around user tasks

- R6a: Replace the first five-way Skills and tools menu with a recognizable
  inventory of tool capabilities and installed skills. An item such as web
  search, browser or speech exposes its separate enabled, configured and
  platform facts, plus known setup needs.
- R6b: Bring supported enablement, configuration and setup entry points together
  in each capability detail. Preserve separate disclosure and toggle actions.
  Setup actions retain explicit effects and actual background-action tracking.
- R6c: Skill browsing/installing remains a clear secondary destination; retain
  usage ordering, provenance, instructions, local edits/archive and Hub actions.
  Agent plugins stay distinguishable and retain their supported inventory/toggles.

### R7. Editors that explain choices and resolve changes

- R7a: Display compression threshold/target as percentages with exact numeric
  editing and a small capacity diagram. Serialize the current fractional contract
  correctly; the diagram explains configuration, not live context occupancy.
- R7b: Explain verified consequences for approval modes, execution limits and
  memory budgets beside controls. Establish the meaning of special values from
  the supported contract before writing explanatory copy.
- R7c: Use a consistent editing pattern: visible target, local edits, count of
  unsaved changes, explicit Save, correct effect labeling, and confirmed readback.
  Failed, partially applied or uncertain saves retain edits and prevent duplicate
  submission. Save remains reachable with the keyboard open.
- R7d: For detected settings conflicts, compare Your value with Current server
  value and let the user deliberately resolve the affected fields without closing
  and reconstructing the form. Revalidate before writing; separate reads/writes
  do not acquire a compare-and-swap guarantee. Scope loss stops the write.
- R7e: Move administration Identity to a dedicated full-screen description/SOUL
  editor with comfortable reading/copying, long-text editing, keyboard room,
  discard protection and existing scoped readback/partial-save behavior.

### R8. Memory as a readable collection

- R8a: Lead with search and retained entries; show Read only concisely with an
  accessible explanation of the limitation. Keep unsupported write actions absent.
- R8b: Use useful titles/excerpts and source metadata when supplied. Details
  prioritize complete comfortable reading and copying. Budget information belongs
  with memory settings; no occupancy meter can be inferred from a configured limit.
- R8c: Give a confirmed empty collection a warm, factual explanation and a Memory
  settings action. Distinguish search-empty, read failure, stale and true empty.

### R9. Search shortcuts and comparable usage

- R9a: Search results show a meaningful owner/destination path. A field result
  opens its one editor, scrolls to the field, and briefly emphasizes it without
  forcing the keyboard open. Include task vocabulary such as API key, timeout
  and voice, an explicit clear action, and originating-tab restoration.
- R9b: Show compact per-model comparisons with formatted calls, tokens and
  estimated cost, sorting and expandable detail. Preserve all existing rolling
  ranges (1/7/30/90/365 days) and input/output/session detail.
- R9c: Include cost-share bars only where reported costs permit a meaningful
  comparison; label the denominator/coverage and estimates. Unknown cost stays
  unknown, zero totals do not divide by zero, and auxiliary breakdowns must not
  be added to totals that already include them.

### R10. Wing warmth and continuity

- R10a: Apply a restrained conversational voice to first-use/empty states.
  Populated pages prioritize current information. Integrate completed scheduled
  task work: summarize next run/latest known outcome and reduce introductory copy
  once tasks exist. Retain its prominent next-run rhythm and supported operations.
- R10b: Preserve list position and context on return from edits, update affected
  summaries, and briefly emphasize changed values. Keep transitions purposeful
  and honor reduced motion, including search-result emphasis.
- R10c: All changed surfaces support 200% text at 320 dp, growing rows, minimum
  48 dp interaction targets, keyboard/focus navigation and accessible status text.
  Independently operable row disclosures/switches must retain separate semantics.

## Boundaries retained from the accepted review

These are constraints on the design, not omitted recommendations:

- Use only established current backend contracts. Memory edits/deletes, per-tool
  MCP writes, automatic repair, new restart commands, unsupported plugin lifecycle,
  fabricated account ownership and unverified model-readiness claims remain out.
- Usage trend charts require time-series data; range totals support comparison,
  not invented history. Memory occupancy needs reliable selected-profile sizes.
- Product-level shared-account inheritance and configured fallback models are
  domain behaviors. They are distinct from compatibility shims. Follow the user's
  clean-target rule: obtain explicit approval before adding or preserving legacy
  interfaces, aliases, schema fallbacks or migration/deprecation behavior as part
  of the implementation. Search vocabulary is discovery text, not a legacy API.
- Preserve chat/composer/Activity, notifications and the completed connection
  journey. Reuse those entry points where needed without redesigning them.
- Actual Flutter/native evidence establishes delivered UI quality; earlier
  captures and generated concept boards are reference material only.

## Review baseline and integration dependency

The review read the administration root, shared widgets, defaults, settings,
providers, capabilities/setup, memory, health/diagnostics, operations, identity,
search and usage. Existing captures supported visual observations but some
predated current source. Scheduled-task files were actively changing at the initial
review and are now committed in `a84abda186ca2b495148fb33939d7a77e6fe0e53`.
Plan 002 records completion; the implementation plan's committed integration
baseline identifies the delivered seams and evidence to reuse.

For R1b/R10a, a task's last-run time or an inactive run conversation does not prove
its outcome. Summaries must show an unavailable outcome when result evidence is
absent, and disclose coverage when completed one-shots have left the inventory.
The existing scheduled-task interface remains the foundation for overview
integration and targeted copy/continuity refinements.

Before implementation, re-read the finished work from the two agents and the
current Studio/ownership documents. The earlier instruction to keep the scheduled
task change focused applies to that work; this separately authorized redesign
starts only after the owner's go. Do not overwrite their work to restore the
review baseline.
