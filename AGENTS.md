# Hermes deployment constraint

Wing runs against **unmodified, vanilla Hermes**. Implement features entirely in
the Android client using APIs available on the user's existing server. Backend
patches, forks, plugins, custom endpoints and required backend upgrades are out
of scope. Backend checkouts are read-only references, not implementation targets.

Verify the stock API before designing a feature. If it cannot support the requested
behavior, state that limitation and discuss a client-only design. Never silently
change shared profile settings to simulate an unsaved voice preview.

# UI design

For UI work, read [the Studio design charter](docs/DESIGN_SYSTEM.md) before changing screens, components, themes, or interaction layouts. It owns the selected appearance, component rules, and behavior-preservation contract. Use its shared tokens for new and existing controls, including light and dark states.

For administration UI, also read [the ownership handoff](docs/design/2026-09-14-administration-handoff.md). It distinguishes shared server providers, profile defaults and overrides, and runtime versus profile health. Planned capabilities and generated mockups are not evidence that a backend operation is implemented.

## Design before implementation

For new screens and layout changes, apply the frontend-design skill's planning
and critique process within Studio's established visual language.

1. State the user's task and primary action. Separate editable controls, passive
   context and temporary status before choosing components.
2. Sketch at least two plausible arrangements; compare visual weight, repeated
   information, taps and reachability. Present the recommended design when the
   user asks for a proposal; a proposal request authorizes design work only.
3. Challenge every heading, card, label and sentence: retain it only if it helps
   the user decide, act or recover. Keep provider/context metadata subordinate
   to controls. Show sample speech through playback; keep its script out of the
   ordinary UI. Give transient saving feedback without permanent success clutter.
4. Before declaring UI complete, inspect actual rendered screens at normal phone
   size, then enlarged text in both themes. Check hierarchy and density as well
   as selection, loading, errors and action reachability. Revise what looks or
   feels wrong; passing widget tests alone does not establish design quality.
