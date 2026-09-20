# Output viewers and downloads

Assistant deliverables (`MEDIA:` references and explicit file links) appear as
file cards with separate **Download** and **Open preview** actions. Download opens
Android's save destination picker; cancelling does not save a file. Open preview
opens the existing full-screen reader, and Back returns to the conversation.
Markdown starts in **Rendered** mode with a **Source** control. Copy message
retains the original authored text, including the server path.

A chat's Outputs list provides another way to find and open references, including
older history. Files are fetched through their original authenticated connection
and profile. Relative text-preview paths resolve against the originating saved
chat's directory; an unavailable directory is an error. Leaving the chat while a
download is pending prevents a late save picker. Old paths may be unavailable.

This follows stock Hermes desktop's `PreviewAttachment`, MEDIA parsing and
Markdown preview at upstream commit
[`0caf219aafdf40522f7bfc3ce8756e4eae463a04`](https://github.com/NousResearch/hermes-agent/tree/0caf219aafdf40522f7bfc3ce8756e4eae463a04/apps/desktop/src),
inspected on 20 September 2026. Android uses a full-screen reader in place of the
desktop side pane. The integration uses stock `/api/fs/read-text`,
`/api/fs/download` and `/api/sessions/{session_id}`; no backend changes are needed.

## Supported reading

| Content | In-app behavior | Boundary |
| --- | --- | --- |
| Markdown and code | Rendered/Source controls, copying, tables and supported diagrams | Keep server truncation notices visible. Download or Save or share retrieves the full file within the download limit. Relative file links use the saved chat directory. |
| Images and SVG | Explicit loading and zoom; SVG uses the restricted diagram viewer | Preserve a useful source or save/open fallback. |
| PDF | Read PDF, Previous/Next page and pinch zoom | Viewing only; no editing, forms, text search or selection. Password-protected/unsupported files can use another app. |
| Audio and video | Play media, timeline, pause and seek through Android controls | Explicit Play; device codecs determine support. No background playback or authenticated-URL streaming. |
| Web links | Browser preview with close/Back, usually Custom Tabs | Browser uses its own login state. No Hermes headers are passed. |
| Self-contained HTML | Open HTML, source view and inline interaction | Full UTF-8 download up to 1 MiB, in the sandbox described below. CDN-dependent pages need an external app. |

PDF/audio/video also offer Open in app. Save or share remains available when a compatible viewer is absent or an in-app format fails. A successful viewer launch does not prove successful playback or rendering.

## Download and cache ownership

Downloads are capped at 32 MiB, checking both declared length and streamed bytes. Disable duplicate delivery while pending. Closing a preview must prevent a late download from launching a viewer. The native bridge rechecks activity lifetime before launch.

Android viewers receive downloaded bytes, safe display filenames and supported MIME types. Sanitize the decoded basename; use UUID cache filenames. Never pass backend credentials, headers, cookies or authenticated URLs to another app.

FileProvider grants temporary read access only to the `delivered_outputs/` cache area. Age/count pruning removes abandoned delivery files. This is temporary viewing storage, not an offline library. Explicitly saved/shared copies have their own destination lifetime.

## PDF and media resources

PDF uses Android `PdfRenderer`, one page at a time, with at most 2,000 pixels on the longest bitmap edge and three open documents. Native operations are serialized. Failed pages can retry without downloading/reopening the document. Close pages, bitmaps, renderer, handles and temporary files, including a late open after the reader closes. Activity destruction and later pruning clean up abandoned resources.

Media uses a private Android activity with `VideoView` and `MediaController`. Leaving pauses and releases playback, including pending preparation. Return prepares the same cached file at the last position, paused; rotation retains that position. Closing removes the file, with later pruning for process-death leftovers. These viewers add no storage permission or background service.

## HTML and diagram sandbox

Interactive HTML uses the complete downloaded bytes, never a truncated text preview. Reject invalid UTF-8 or files over 1 MiB with a Save or share alternative. Inline scripts/CSS and embedded images run in a fresh opaque-origin iframe without storage, parent access, native bridge or Hermes credentials.

Content policies and native interception block external resources, navigation, forms, workers and nested frames. This is not complete network isolation: WebRTC ICE/data-channel networking is not reliably covered by those controls. Remove temporary frames on replacement and close.

Mermaid and SVG have a separate restricted offline renderer with tighter source limits. See [Diagram previews](DIAGRAM_PREVIEWS.md) for vendor versions, licenses and update checks.

Web links accept only HTTP/HTTPS with a host and no URL user information. Custom Tabs can fall back to the external browser or the launcher's WebView path; failure remains visible. No authenticated resource proxy is added for arbitrary pages.

Native PDF/image/SVG zoom and common media playback were exercised against real Hermes downloads during September acceptance. HTML browser fixtures establish sandbox behavior, not exhaustive native phone coverage. See [Testing](TESTING.md).
