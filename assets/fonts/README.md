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

## Project icons

`codicons.ttf` is the unmodified font from Microsoft’s [`@vscode/codicons` 0.0.45](https://www.npmjs.com/package/@vscode/codicons/v/0.0.45), used by Hermes Desktop at commit `8f817911723e3ec13e7f47fc022fdcc9e2149354`. It retains Microsoft attribution and the [CC BY 4.0 license](CODICONS-LICENSE). `ProjectIconGlyphs` maps the font’s stock names to constant Flutter glyphs. The selectable catalogue is curated separately.
