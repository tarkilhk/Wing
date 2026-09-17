# Wing capitalization

On 17 September 2026, the owner requested **Wing** as the official identity
throughout the design language and asked for the branding assets to be
regenerated. Use a capital **W** followed by lowercase **ing** in the drawn
wordmark as well as prose, app labels and repository identity.

Keep the rounded lettering, three pointed feathers above the i, winking
portrait and navy/cream/mint palette. The taller W makes the capitalization
legible while retaining the existing width and baseline in the app.
Package identifiers, native channels and file names remain lowercase.

## Assets and implementation

- [Identity board](images/wing-identity-board.png): regenerated brand board.
- [README banner](images/wing-readme-hero-clean.png): regenerated masthead.
- [Arrival concepts](images/wing-arrival-concepts.png): regenerated concept artwork, not a screenshot.
- [Light welcome](images/wing-welcome-light.png) and
  [dark welcome](images/wing-welcome-dark.png): actual Flutter widget renders.
- [Production wordmark](../../lib/core/widgets/wing_wordmark.dart): scalable
  lettering shared by welcome and connection guide screens.

The portrait-only launcher and notification symbols contain no wordmark.
Their production artwork remains the selected portrait, wing and caduceus.

## Validation

- Ten existing welcome, release-link and application-identity tests passed.
- Both existing first-connection render tests passed; actual Flutter output was
  inspected in light and dark themes at 360 dp with normal text and 320 dp with
  doubled text. The larger-text layout scrolls to reach its actions.
- The regenerated board, banner and concept artwork were visually inspected
  for capitalization, feather accents, portrait continuity and copy.
- Dart formatting checks and focused Flutter analysis passed for the changed
  source and test files.

## Regeneration prompts

The three raster edits use the built-in image generation tool, each with its
existing image as the edit target. The production wordmark is edited directly
in its Flutter vector source, and welcome screenshots are rendered from Flutter.

### board

Use case: text-localization. Edit only the supplied existing Wing branding asset to adopt official title-case wordmark 'Wing', spelled capital W then lowercase i n g. The W must be visibly taller than lowercase i/n/g bodies, a true rounded capital W with four diagonal strokes, not an enlarged lowercase w or symbol. Keep rounded monoline character and baseline; preserve all three pointed feather accents over the lowercase i, one small left cream/navy feather and two mint right feathers, with a visible gap. Preserve the exact winking woman illustration, face, hair, headphones and earcup wing; preserve layout, other copy, colors #0C304A navy, #FFF9EB cream, #C6EED5 mint. No terminal periods on taglines. Do not add content. Edit target: identity board. Replace every lowercase wing wordmark in all THREE placements with 'Wing': main top right, lower middle splash card, lower right announcement card. Replace top-left '01 / WINK' heading with 'Wing'. Ensure cream palette hex caption reads exactly '#FFF9EB'. Keep remaining board structure, portrait, secondary mark, graphic element, swatches and typography specimen identical. Same 1536x1024 landscape framing.

### hero

Use case: text-localization. Edit only the supplied existing Wing branding asset to adopt official title-case wordmark 'Wing', spelled capital W then lowercase i n g. The W must be visibly taller than lowercase i/n/g bodies, a true rounded capital W with four diagonal strokes, not an enlarged lowercase w or symbol. Keep rounded monoline character and baseline; preserve all three pointed feather accents over the lowercase i, one small left cream/navy feather and two mint right feathers, with a visible gap. Preserve the exact winking woman illustration, face, hair, headphones and earcup wing; preserve layout, other copy, colors #0C304A navy, #FFF9EB cream, #C6EED5 mint. No terminal periods on taglines. Do not add content. Edit target: README hero banner. Replace only left wordmark 'wing' with 'Wing'. Preserve wide 3:1 aspect ratio, portrait on right, same two supporting lines verbatim: 'Your agent, with you' and 'An Android companion for Hermes Agent'. Preserve all margins and simple navy field.

### arrival

Use case: text-localization. Edit only the supplied existing Wing branding asset to adopt official title-case wordmark 'Wing', spelled capital W then lowercase i n g. The W must be visibly taller than lowercase i/n/g bodies, a true rounded capital W with four diagonal strokes, not an enlarged lowercase w or symbol. Keep rounded monoline character and baseline; preserve all three pointed feather accents over the lowercase i, one small left cream/navy feather and two mint right feathers, with a visible gap. Preserve the exact winking woman illustration, face, hair, headphones and earcup wing; preserve layout, other copy, colors #0C304A navy, #FFF9EB cream, #C6EED5 mint. No terminal periods on taglines. Do not add content. Edit target: three-panel arrival concept board. Replace both lowercase wing wordmarks in light and dark welcome panels with 'Wing'. Keep native launch panel unchanged and all phone UI labels, artwork and relative layout exactly as in original. Same 1536x1024 framing. This is only capitalization, no new UI.
