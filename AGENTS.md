# Maintainability purpose

Make Wing easy to maintain and change, with clear module boundaries that let
agents work independently. Keep this purpose in view throughout each task.

- Give each business fact and workflow one explicit owner. Views render immutable
  observations and forward user intent; owners decide, persist and coordinate I/O.
- Prefer small interfaces that hide implementation details. Keep changes local to
  the responsible module and remove superseded code after checking its callers.
- Protect each incorrect pattern encountered with a small, deterministic linter
  where feasible. Use behavioral regressions for properties static checks cannot
  establish, such as lifetime, uncertainty and asynchronous ordering.
- Prioritize completed production migrations and dead-code removal. Run focused
  checks for each change and broad verification at integration milestones.
- For parallel work, assign explicit module/file ownership and integrate bounded
  handoffs before starting dependent changes.

For feature work, behavior fixes, refactoring or deletion, read and follow
[maintain-feature-architecture](tools/agent_skills/maintain-feature-architecture/SKILL.md).
It routes ownership decisions, documentation updates and applicable checks.
The completed cleanup's evidence lives in [plans/README.md](plans/README.md);
use the maintained [architecture map](docs/ARCHITECTURE.md) for new work.

Before committing in a fresh checkout, enable the tracked lint hook using
`python3 scripts/install_git_hooks.py`. See [local commit checks](CONTRIBUTING.md#local-commit-checks)
for toolchain setup and staged-snapshot behavior.

# Hermes deployment constraint

Wing targets **the latest upstream, unmodified Hermes**, including changes on
upstream main. Before designing or implementing an integration, verify the current
stock API and record the inspected commit; a local checkout or an older deployed
server does not define the target. Implement features entirely in the Android
client. Backward compatibility requires the user's explicit approval.

Backend patches, forks, plugins and custom endpoints are out of scope. Backend
checkouts are read-only references. Updating a deployed server is a separate
deployment action; targeting current upstream does not authorize an upgrade.

Verify the stock API before designing a feature. If it cannot support the requested
behavior, state that limitation and discuss a client-only design. Never silently
change shared profile settings to simulate an unsaved voice preview.

# Performance testing

For instrumentation, benchmarking or device profiling, read
[Performance investigation](docs/PERFORMANCE.md) before building or recording
results. It owns release gating and private evidence storage. Recorded
measurements belong outside public Git; public docs retain procedures and
regression contracts.

# UI design

For UI work, read [the Studio design charter](docs/DESIGN_SYSTEM.md) before changing screens, components, themes, or interaction layouts. It owns the selected appearance, component rules, and behavior-preservation contract. Use its shared tokens for new and existing controls, including light and dark states.

For Activity tools, Tasks, Agents, reasoning, goals, recurring work, processes,
or their viewers, read and follow
[design-wing-activity](tools/agent_skills/design-wing-activity/SKILL.md) before
planning or editing. It applies USER-VALUE-FIRST selection and the charter's
shared activity family, with field/action decisions and actual render checks.

For administration UI, also read [the ownership handoff](docs/design/2026-09-14-administration-handoff.md). It defines profile-owned provider credentials and defaults, server operations, and runtime versus profile health. Planned capabilities and generated mockups are not evidence that a backend operation is implemented.

## Design before implementation

For new screens and layout changes, apply the frontend-design skill's planning
and critique process within Studio's established visual language.

1. State the user's task and primary action. Separate editable controls, passive
   context and temporary status before choosing components.
2. Sketch at least two plausible arrangements; compare visual weight, repeated
   information, taps and reachability. Compare internally when implementation is
   requested and continue through delivery. Present the recommended design when
   the user asks for a proposal; a proposal request authorizes design work only.
3. Challenge every heading, card, label and sentence: retain it only if it helps
   the user decide, act or recover. Keep provider/context metadata subordinate
   to controls. Show sample speech through playback; keep its script out of the
   ordinary UI. Give transient saving feedback without permanent success clutter.
4. Before declaring UI complete, inspect actual rendered screens at normal phone
   size, then enlarged text in both themes. Check hierarchy and density as well
   as selection, loading, errors and action reachability. Revise what looks or
   feels wrong; passing widget tests alone does not establish design quality.
   For repeated components, complete the charter's
   [family acceptance procedure](docs/DESIGN_SYSTEM.md#family-acceptance-procedure),
   including nested framing, footer colors and the actual served preview.
