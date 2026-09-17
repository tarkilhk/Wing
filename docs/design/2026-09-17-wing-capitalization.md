# Wing capitalization

On 17 September 2026, the owner selected the slimmer capital-W banner as the
final Wing wordmark. The official name is **Wing**, with a capital **W** and
lowercase **ing**, throughout artwork, prose, app labels and repository identity.

The W has modest extra height and the same optical weight as ing. Its diagonal
strokes are slimmer to avoid a bold or swollen initial. Keep its open internal
spaces, rounded ends, shared baseline and balanced width. The selected banner,
rather than a numerical height ratio, is the visual reference.

Keep the three pointed feathers above the i, winking portrait and navy/cream/mint
palette. Package identifiers, native channels and file names remain lowercase.

## Assets and implementation

- [Approved README banner](images/wing-readme-hero-slim-w.png): the exact selected
  image, copied without further generation. Its distinct URL replaces the
  previous banner URL in the README.
- [Identity board](images/wing-identity-board.png): matching slimmer-W lettering.
- [Arrival concepts](images/wing-arrival-concepts.png): matching concept artwork,
  not a screenshot.
- [Light welcome](images/wing-welcome-light.png) and
  [dark welcome](images/wing-welcome-dark.png): actual Flutter widget renders.
- [Production wordmark](../../lib/core/widgets/wing_wordmark.dart): scalable
  lettering shared by welcome and connection guide screens. The W uses a
  28-unit stroke against the 36-unit lowercase stroke for equal optical weight.

The portrait-only launcher and notification symbols contain no wordmark.
Their production artwork remains the selected portrait, wing and caduceus.

## Validation

- Ten existing welcome, release-link and application-identity tests passed
  against the current main dependencies.
- Both existing first-connection render tests passed. Actual Flutter output was
  inspected in light and dark themes at normal and doubled text; the larger
  layout scrolls to reach its actions.
- The approved banner was copied byte-for-byte. Matching board and concept
  artwork were inspected for stroke weight, proportions, feather accents,
  portrait continuity and copy.
- Dart formatting, focused Flutter analysis and Git whitespace checks passed.

## Generation prompts

The raster artwork uses the built-in image generation tool. The production
wordmark is edited in its Flutter vector source; welcome screenshots are
rendered from Flutter. The following are the actual prompts; the selected
image remains authoritative when a generation differs from a numerical hint.

### Approved banner

Use case: precise-object-edit / text-localization. Make ONE careful typographic edit to this exact Wing README banner, for a preview. The owner wants an uppercase W, but explicitly rejects a bold/fat/heavy W. Replace just the initial letter with a conventional, clean CAPITAL W in the SAME OPTICAL WEIGHT as the lowercase i n g. Do not scale up the existing chunky w. Redraw the W as four clean straight diagonal strokes with gently rounded ends and generous open negative spaces. Each diagonal must be visually NO THICKER than the vertical stem of the adjacent i. Because diagonals and joins look heavier, use slightly thinner strokes for the W (about 85–90% of the i stem thickness) to achieve equal optical weight. Keep the joints light; no swollen/filled central diamond, no bulbous merged diagonals, no bold weight. All three top peaks should be recognizably at capital height with the middle peak only slightly lower. Moderate capital height only: W baseline at approximately y=390 and cap top y=205 in this 2048x683 reference; lowercase n stays at y=245 to390. The W is thus only about 25% taller than the n, NOT a giant initial. Keep the W within roughly x=237..486 and preserve clear space before the i. Keep the entire i, n, g and their spacing, the three feather accents over i, portrait, face, headphone emblem, background, palette, text, size, position and framing unchanged. The target reads 'Wing' in a coherent single regular rounded type weight. Keep exact supporting text 'Your agent, with you' and 'An Android companion for Hermes Agent'. Preserve the original 3:1 aspect ratio. No extra headings, annotations, labels, comparisons or design-board layout. Output just the edited full banner.

### board

Use case: precise-object-edit / identity-preserve. Image 1 is the edit target; image 2 is the OWNER-APPROVED Wing wordmark reference. Update only the W letterforms in image 1 to match EXACTLY the slimmer, modest-height capital W in image 2. Match its narrow, uniform rounded diagonal strokes and open internal spaces; the W must NOT be bold, fat, enlarged or dominating. It has equal optical weight to ing and only modest extra height. Do not interpret capital as larger/bolder. The approved image 2 controls the geometry and weight. Scale that W proportionally to each existing wordmark. Keep lowercase ing, feather cluster, baseline and wordmark width consistent with original. Preserve all portraits, face, hair, headphone earcup emblems, illustration edges, layout, other text, labels and navy/cream/mint palette exactly. No new design. Edit target: identity board. Apply matching slender W to the main top-right logo, lower middle splash card, lower right announcement card and small top-left Wing heading. Preserve all other board elements and 1536x1024 framing.

### arrival

Use case: precise-object-edit / identity-preserve. Image 1 is the edit target; image 2 is the OWNER-APPROVED Wing wordmark reference. Update only the W letterforms in image 1 to match EXACTLY the slimmer, modest-height capital W in image 2. Match its narrow, uniform rounded diagonal strokes and open internal spaces; the W must NOT be bold, fat, enlarged or dominating. It has equal optical weight to ing and only modest extra height. Do not interpret capital as larger/bolder. The approved image 2 controls the geometry and weight. Scale that W proportionally to each existing wordmark. Keep lowercase ing, feather cluster, baseline and wordmark width consistent with original. Preserve all portraits, face, hair, headphone earcup emblems, illustration edges, layout, other text, labels and navy/cream/mint palette exactly. No new design. Edit target: three-phone arrival concept board. Apply matching slender W to both the light and dark welcome wordmarks. Keep all phone UI, all portraits, text, feather accents, and the native launch panel unchanged. Preserve 1536x1024 framing.

### Board stroke refinement

Precise correction to Image 1 (brand board), matching Image 2 (approved banner). The W in the large top wordmark still looks too bold. Thin ONLY the four W letters on this board: main top wordmark, lower splash card, lower announcement card, top-left small heading. Reduce W diagonal stroke widths by approximately 20%, to about 75–80% of the adjacent i stem width, keeping each W's overall dimensions, centerline path, round terminals, baseline and modest height. This opens the interior navy/cream gaps and makes the W visibly leaner, EXACTLY like the approved banner in image 2. Do not thicken or resize the lowercase ing letters. Preserve EVERYTHING else pixel-faithfully: all feather accents, portraits, hair, face, headphones, colors, wording, swatches, card arrangement and entire board framing. Do not make the W taller or wider, do not use bold. Output the complete edited board.
