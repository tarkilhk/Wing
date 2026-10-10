# Shared action icons

`wing-icons.ttf` contains Lucide’s `square-pen` (U+E175), selected for every
New chat action, and `git-fork` (U+E28C), selected for answer branching.
Flutter refers to them through `WingIcons.newChat` and `WingIcons.fork`.
The Android `ic_shortcut_new_chat.xml` drawable uses the matching square-pen paths.

Source: [`lucide-static` 0.468.0](https://www.npmjs.com/package/lucide-static/v/0.468.0),
`font/lucide.ttf` and `icons/square-pen.svg` / `icons/git-fork.svg`.
The git-fork SVG geometry is identical to Lucide 0.577.0 used by upstream desktop
`GitForkIcon` at Hermes commit `dce1e9b37581dd62e480a9064dc04a709c2940d3`.
Both retain the [ISC license](LUCIDE-LICENSE).

To reproduce the subset using FontTools, load the source font with `TTFont`,
create `subset.Options()` with `recalc_timestamp = False`, populate a
`subset.Subsetter` with `unicodes=[0xe175, 0xe28c]`, subset the font and save it as
`wing-icons.ttf`. Keep the original codepoints and outlines; Flutter’s font-family
alias is declared in `pubspec.yaml`.
