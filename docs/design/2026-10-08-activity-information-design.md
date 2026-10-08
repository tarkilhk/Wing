# Activity information design

Research inspected on 8 October 2026 for Wing's compact, inline tool details.
The [Studio charter](../DESIGN_SYSTEM.md) owns implementation choices. This note
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

## Accepted Studio rules

These are Wing design choices informed by the findings and the owner's requests.

- Use Roboto for human prose and section labels; use the shared monospace style
  for code, commands, paths, source text and literal console output. Keep body
  passages comfortably spaced. Use weight, proximity and selective emphasis
  before adding another font family. Use tabular figures for aligned timings
  and counts. A future code-font change needs phone rendering comparisons,
  including punctuation and ambiguous characters, rather than a brand-based
  choice.
- Render Markdown for authored explanations and analyses where its headings,
  lists, emphasis, links or tables help reading. Preserve code fences. Render
  file contents, replacement strings, patches and console output literally;
  Markdown-looking characters in those values are data.
- Give each expanded activity one grouped surface aligned with its leading
  icon. Use short, specific section labels for the requested operation and the
  reported result. Keep paths, timing, counts and status subordinate. Separate
  sections with thin rules or compact spacing instead of more nested cards.
- Show enough content to understand the request and response. Offer icon-only
  expansion, wrapping and full-view actions for lengthy text, plus secondary
  raw details. Local previews must be identified as previews. Expanding them
  reveals already returned content; it must not suggest that omitted backend
  content has been fetched.
- Keep copy and other icon-represented actions icon-only everywhere. Provide
  precise tooltips and accessible names, reachable targets and temporary
  feedback. Wrap or reposition toolbars when space is tight. Follow the charter's
  [accepted activity family](../DESIGN_SYSTEM.md#accepted-activity-detail-family)
  for compact detail controls; keep their chosen targets while text reflows.
- Use semantic color sparingly for actual errors, reported outcomes and diff
  additions/deletions. Retain text or glyph cues and readable contrast in both
  themes. Ordinary activity completion footers use the accepted family's neutral
  convention, including backend-confirmed success; errors/warnings and supplied
  diff changes carry their explicit accents.
- Preserve exact supplied values for selection and copying, regardless of
  display wrapping or preview limits. Requested changes and reported changes
  are separate facts. Show totals, exit codes, verification, diffs and analysis
  only when supplied by the backend; tool completion alone establishes none
  of them. Treat a native-vision image receipt as an image loaded for the agent,
  rather than inventing an analysis result.
- Inspect rendered phone layouts in both themes at ordinary size and at
  320 dp/200% text. Check long paths, Markdown structure, dense toolbars, literal
  output, errors and preview expansion. Keep horizontal scrolling inside the
  code or table region that needs it; prose and its surrounding controls reflow.

## Scope and limits

This research concerns presentation, not changes to the Hermes protocol or
backend. Backend capability evidence belongs in [Tool activity](../TOOL_ACTIVITY.md).
The rules retain Studio's selected appearance and do not authorize
compatibility layers, new dependencies, server changes or deployment.
