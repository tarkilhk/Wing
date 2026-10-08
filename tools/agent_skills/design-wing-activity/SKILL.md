---
name: design-wing-activity
description: Design or revise Wing Activity tools, Tasks, Agents, reasoning, goals, recurring work, processes and their viewers with deliberate user-value-first information and actions.
---

# Design Wing Activity

Apply USER-VALUE-FIRST within Studio. Paths are relative to the Wing checkout.
The [Studio charter](../../../docs/DESIGN_SYSTEM.md#user-value-first-activity)
owns field placement, action eligibility, icon vocabulary and family geometry;
this skill owns the execution process. Read that section and the linked family
rules before choosing a layout.

## Decide

1. Establish [backend API coverage](../../../docs/DESIGN_SYSTEM.md#backend-api-coverage)
   for every candidate field in production and prototypes. Done when each has a
   supported API source, exact meaning and scope; omit unsupported observations.
   Inspect the affected presentation owner, renderer, backend observations and
   real fixtures. State the user's question: what was attempted, what actually
   happened, and what can they use or act on? Read
   [the activity contract](../../../docs/TOOL_ACTIVITY.md) for backend evidence.
   Done when requested intent and received outcome are separate, with unknown
   or partial facts qualified.
2. Read the maintained [field decisions](../../../docs/design/activity-field-policy.md),
   then build a decision table for every affected family, every received field and
   every action. Record user signal/value, placement (main payload, quiet title
   metadata or Raw details), exact copy/open scope and eligibility. Include
   absent/empty, short/long, failure and partial-result cases. Account for each
   candidate action, including actions intentionally omitted. Done when no
   visible field or control relies on a blanket renderer default.
3. Compare at least two plausible arrangements internally. Judge hierarchy,
   duplicated meaning/actions, metadata weight, taps, reachability and enlarged
   text. Select the arrangement that makes intent and achievement clearest.
   Done when each main item has a stated user value and each icon has a useful
   distinct scope. Resource labels follow the charter's one-line filename/path
   popup rule; validate locator semantics separately from compact display.
   An implementation request authorizes continuing to build;
   present a proposal only when the user requested one.

## Build and verify

4. Implement the selected decisions through the existing presentation owner
   and shared family components. Keep technical evidence available in Raw
   details and exact reusable payloads intact. Follow
   [maintain-feature-architecture](../maintain-feature-architecture/SKILL.md)
   for ownership/manifest updates. Done when every table decision matches the
   delivered source and superseded rendering/actions are removed.
5. Inspect actual rendered affected family members together in light and dark
   at ordinary phone size and 320 dp/200% text. Include short and overflowing
   payloads, actionable resources, long metadata, failures and partial results.
   Check all visible insets, source/prose typography, neutral completion,
   icon order/scope/eligibility, scrolling and viewer recovery. Include long
   filenames, exact path popups and malformed locators; verify that shortening
   names leaves resource actions pointed at the original backend identity.
   Verify preview
   image bytes come from those renders. Revise discrepancies, run focused
   behavioral checks and record remaining limits. Done when the decision table
   and render matrix account for every affected family; passing tests or a
   screenshot of one card do not establish family acceptance.

Report changed user value, specific rendered properties checked and any
unverified states. A new owner report reopens the relevant decision/render check.
