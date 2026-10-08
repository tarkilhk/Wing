# Activity information design

Research inspected on 8 October 2026 for Wing's compact, inline tool details.
The [Studio charter](../DESIGN_SYSTEM.md) owns presentation policy. This note
separates external evidence from Wing's accepted rules; it does not establish that
a screen or backend capability has been implemented.

## Findings from primary sources

### Typography should express the role of the text

Material 3 organizes type into display, headline, title, body and label roles.
It recommends body faces that remain comfortable in long passages at small
sizes, avoiding decorative faces for body text. Its body guidance suggests line
height around 1.5 times the font size; tabular figures improve alignment for
tables and frequently changing values. These are role and readability
recommendations, rather than a requirement to introduce additional font
families. [Material 3: Applying type](https://m3.material.io/styles/typography/applying-type)

Material's earlier typography guidance suggests approximately 40–60 characters
for English body lines and 20–40 for short text. These are useful measures on
wider layouts, not a minimum line length that a narrow phone must reach by
shrinking text. [Material: Understanding typography](https://m2.material.io/design/typography/understanding-typography.html)

### Modest, descriptive hierarchy helps scanning

NNGroup's original eye-tracking examples show readers using distinctive,
descriptive subheadings to find relevant passages. Consistent heading styles
and clear proximity between labels and content support this scanning; overly
bright or oversized headings can resemble advertising. Chunking related
information and removing unnecessary words matter alongside typography.
[NNGroup: Layer-cake scanning](https://www.nngroup.com/articles/layer-cake-pattern-scanning/)

This supports a small number of predictable visual roles in an activity card.
Applying that evidence to tool receipts is a design inference; the study did
not compare Wing activity layouts or establish a best code font.

### Disclosure reduces the burden of uncommon details

NNGroup describes progressive disclosure as showing the most useful controls
first and deferring advanced or infrequent ones. The secondary level still
needs a clear route and sensible content selection. Hiding important failures
or the information needed to choose an action would undermine that purpose.
[NNGroup: Progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/)

### Structure needs to survive changes in presentation

W3C's information-and-relationships guidance requires the structure expressed
visually to be programmatically available or available in text. Headings,
lists, tables and labelled groups should retain their meaning when read with
assistive technology. Rendering authored Markdown can preserve those
relationships; a font change alone cannot provide them.
[W3C: Info and relationships](https://www.w3.org/WAI/WCAG22/Understanding/info-and-relationships.html)

### Reflow matters more than squeezing everything onto one line

WCAG 2.2's reflow criterion addresses content at a width equivalent to 320 CSS
pixels. W3C explains that meaningful code indentation and data tables can need
their own horizontal scrolling, while surrounding prose continues to reflow.
The exception belongs to the content requiring it, not the whole page.
[W3C: Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)

Resize Text addresses enlargement to 200% without losing content or function.
Text Spacing addresses user-adjusted spacing without loss; its 1.5 line-height
test value is not a prescribed default line height.
[W3C: Resize text](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html),
[W3C: Text spacing](https://www.w3.org/WAI/WCAG22/Understanding/text-spacing.html)

### Color and icon actions need other ways to communicate

WCAG specifies at least 4.5:1 contrast for ordinary text and 3:1 for qualifying
large text. Important component and graphic cues need 3:1 against adjacent
colors. Color alone cannot express meaning, so a red/green diff needs its
deletion/addition markers, and outcome color needs a readable outcome or
recognizable shape.
[W3C: Text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html),
[W3C: Non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html),
[W3C: Use of color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)

Icon controls need an accessible name describing their purpose. WCAG's web
target-size minimum is 24 by 24 CSS pixels, with specified exceptions; that is
distinct from Wing's general 48 dp target policy and the owner's accepted
32 dp activity-detail exception. The criterion does not
require visible text beside an icon.
[WCAG 2.2: Non-text content](https://www.w3.org/TR/WCAG22/#non-text-content),
[W3C: Target size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)

WCAG is a web standard. WCAG2ICT provides informative guidance for applying its
principles to native software. Wing's 320 dp/200% checks are practical native
verification targets; screenshots alone do not demonstrate WCAG conformance.
[W3C: WCAG2ICT](https://www.w3.org/TR/wcag2ict-22/)

## Applying the evidence in Wing

The authoritative Wing rules live in the charter's
[USER-VALUE-FIRST Activity policy](../DESIGN_SYSTEM.md#user-value-first-activity),
[action/viewer decisions](../DESIGN_SYSTEM.md#activity-actions-and-viewers) and
[shared activity family](../DESIGN_SYSTEM.md#accepted-activity-detail-family).
The repository-local
[design-wing-activity skill](../../tools/agent_skills/design-wing-activity/SKILL.md)
turns those rules into field/action decisions and actual render checks. This
research note supplies evidence and design rationale rather than a second set
of accepted rules.

The progressive-disclosure findings support deliberately selecting the content
that helps a user understand intent and actual achievement. Wing applies that
principle by keeping useful payloads in the main card, execution options as
quiet title metadata and diagnostic plumbing in Raw details. Assigning these
particular fields to those levels is a Wing design decision, not a conclusion
measured by the cited studies.

Typography and scanning findings support stable roles and proximity: source
stays literal and monospace, authored prose can retain Markdown structure, and
controls sit beside the payload they affect. Wing's one eye vocabulary and
useful-only copy/viewer eligibility similarly follow the owner's directions;
external sources do not establish a particular icon order or action count.

The shared 8 dp framing and neutral Completed treatment are accepted Wing
choices. The current 160 dp inline text cap is a revisable implementation
default. Neither the research nor the owner's spacing feedback establishes
blanket acceptance of the earlier information hierarchy, every visible backend
field or every viewer/copy action.

A decision table and normal/enlarged light/dark renders test whether the actual
arrangement communicates the intended hierarchy and keeps actions reachable.
Behavioral checks separately establish exact copying, action eligibility and
recovery. Test totals or one isolated screenshot do not establish uniformity,
user value or accessibility conformance.

## Scope and limits

This research concerns presentation, not changes to the Hermes protocol or
backend. Backend capability evidence belongs in [Tool activity](../TOOL_ACTIVITY.md).
The rules retain Studio's selected appearance and do not authorize
compatibility layers, new dependencies, server changes or deployment.
