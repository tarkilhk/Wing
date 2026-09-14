# Hermes visual design exploration

Status: the owner selected C, Studio, for refinement on 14 September 2026. A and B are unselected. Revision 2 details remain under review. No app implementation authorized by this study.

The owner requested design work only on 14 September 2026, specifically rejecting large rounded default buttons. This study compares three visual systems using the same Chats, Conversation and App settings content. Sample content is illustrative, not live account data.

## Product boundaries

The [product plan](../PRODUCT_PLAN.md) continues to define behavior. Keep the hamburger drawer, projects inside Chats, explicit connection/profile scope, ordinary send behavior and the context indicator integrated into the composer edge. General-purpose assistant use is the priority. Existing historical design documents are references, not approval for this redesign.

## Candidates

| Direction | Structure and character | Controls | Tradeoff |
| --- | --- | --- | --- |
| A, Folio | Warm paper, serif headings, flat ruled lists, answer prose with generous reading space | Olive rectangles, 2 dp radius, text actions | Distinctive and good for reading; serif headings may feel too bookish for administration |
| B, Instrument | Dark graphite, compact continuous lists, small toolbar, aligned transcript | Pale blue rectangles, 4 dp radius, outlined secondary actions | Efficient for frequent use; strongest risk of feeling austere |
| C, Studio | Light neutral canvas, mint identity, a few grouped lists, humanist sans | Deep green rectangles, 6 dp radius; groups at 8 dp | Most coherent evolution of the current app; less visually distinctive than Folio |

The owner selected C, Studio, then requested bottom New chat, top search, preservation of Activity/tool and composer interactions, graphical context usage and a fully planned dark theme. See the [design system](../DESIGN_SYSTEM.md) for the selection and preservation contract.

## Shared design proposals

- Primary action paint is about 40 dp high within a minimum 48 dp touch area. Secondary actions use outline or text treatments. Reducing visual bulk must not reduce usable touch targets.
- Use rectangles with the chosen small radius. Reserve circles for avatars and genuine circular indicators. Remove capsule-shaped action buttons and the stack of rounded dock, field and button containers.
- Use 16 sp body text, 12-13 sp metadata, clear type weight hierarchy and a 4 dp spacing rhythm. Support user text size without fixed-height clipping.
- Distinguish action priority through fill and placement. A row action should not compete with the primary page action.
- Show status with text and an icon as well as color. Accent choices must not change the meaning of warning, failure or completion.
- Keep assistant prose outside message bubbles. Collapse tool details into a labeled disclosure, while questions and approvals stay visible.
- Extend the selected system to Connections, Activity, Outputs, App settings and Hermes administration. Settings and operations must show their actual device, profile or backend scope.

Exact colors and dimensions in the boards are design targets. Generated raster mockups are visual references, not pixel-exact component specifications or verified contrast results. The chosen system still needs explicit light/dark tokens and disabled, pressed, focus, error, empty, loading and large-text states documented before implementation.

## Selection and permanent record

The selected direction and owner corrections are recorded in `docs/DESIGN_SYSTEM.md` and linked from the documentation index and product plan. The revised boards and exact tokens remain proposals until reviewed. The initial board's top New chat placement and verbose context row are superseded.

The owner subsequently selected the context ring beside the model selector. This supersedes the revision 2 recommendation to retain the edge fuse. Remaining screen/state reviews are listed in the design system.

No source, dependencies, app behavior or tests were changed for this study.

## Visual references

Boards are generated with the built-in image-generation tool. Exact initial prompts are retained in [2026-09-14-prompts.md](2026-09-14-prompts.md). See the [original Studio board](images/studio-v1.png) and [revision 2 theme board](images/studio-v2-themes.png).
