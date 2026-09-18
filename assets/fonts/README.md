# New chat icon

`wing-icons.ttf` contains only Lucide's `square-pen` (U+E175), selected for every
New chat action. Flutter refers to it through `WingIcons.newChat`. The Android
`ic_shortcut_new_chat.xml` drawable uses the matching SVG paths.

Source: [`lucide-static` 0.468.0](https://www.npmjs.com/package/lucide-static/v/0.468.0),
`font/lucide.ttf` and `icons/square-pen.svg`. Both retain the [ISC license](LUCIDE-LICENSE).

To reproduce the subset using FontTools, load the source font with `TTFont`,
create `subset.Options()` with `recalc_timestamp = False`, populate a
`subset.Subsetter` with `unicodes=[0xe175]`, subset the font and save it as
`wing-icons.ttf`. Keep the original codepoint and outline; Flutter's font-family
alias is declared in `pubspec.yaml`.
