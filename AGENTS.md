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
