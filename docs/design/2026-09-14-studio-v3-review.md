# Studio revision 3 review

Status: design proposals awaiting visual review. The owner authorized continuing design work after selecting Studio and the context ring. No application code was changed.

Administration update: the owner selected Profile / Server / Health tabs in the parallel administration work. The [audited administration handoff](2026-09-14-administration-handoff.md) supersedes this board's single-page navigation and refines ownership. Retain the board as a Studio style/form reference, not the final administration information architecture. Conversation proposals are unaffected.

## What this pass examines

- A busy conversation with the keyboard open, a multiline draft, one attachment and a queued follow-up, in light and dark themes.
- A narrow-phone variant with larger text and a long model label.
- A dense administration overview in light and dark themes.
- A profile editor with the keyboard open and a reachable Save action, plus representative form states.

The [design system](../DESIGN_SYSTEM.md) remains the record of owner decisions. The boards use illustrative content. They are not screenshots of the running application and cannot prove pixel fit, keyboard behavior, text scaling or touch accessibility.

## Conversation proposals

Use the selected context ring in the existing composer control row. Keep attachment, voice and Send/Stop controls available. Reserve separate interaction areas for the ring and model selector. A long model name can use an ellipsis on the first line with reasoning on the second line, without changing the actual model identifier. The full identity remains available through the existing picker when enabled. While busy, retain the current model-change restriction and show a readable disabled selector.

Let the transcript take the remaining viewport above the status, queue, draft and keyboard. Keep status and queued follow-ups outside transcript scrolling. Preserve queue edit/delete access and the bounded queue area. The selected ring adds no permanent token text or composer-edge decoration.

The narrower illustration depicts an independently user-collapsed Activity section. Opening the keyboard or changing width must not automatically collapse Activity or reset its tab/scroll state. Keep the existing borderless disclosure, nested rows and guide geometry. More available space is not a reason to decorate tool results with new cards or timeline dots.

The keyboard is illustrative and controlled by Android and the user's keyboard app. Studio controls app insets and composer position, not keyboard appearance. Keep the compose actions directly above the keyboard and apply the bottom system inset only where needed. Support multiline editing without changing Enter/Send semantics.

At narrow widths and larger text, preserve touch targets and accessible labels before retaining a decorative model icon. If the control row cannot fit at the user's text size, allow a deliberate additional control row instead of shrinking text, overlapping targets or hiding Send/Stop. That extreme fallback still needs an explicit layout specimen.

## Administration proposals

Group profile-owned entries together: current profile, description, profile default model/provider and Skills and tools. Place backend version and update entry points under a separate scope label identifying the entire backend. Usage and diagnostics keep their actual scope and existing load/refresh behavior.

Use compact list rows and actions attached to the relevant group. The overview has no global Save because it does not edit a single form. Prefer a text Refresh action, an outlined Updates entry and one clear primary action when editing. Do not add restart controls or imply additional backend capabilities.

For the existing description/SOUL editor, propose a shallow action footer above the keyboard so Save remains reachable while editing a long SOUL. The content scrolls independently. This is a presentation proposal, not a change to save semantics. Keep explicit Close/Cancel, existing unsaved-change confirmation, disabled/loading states and field-level partial-save handling. Do not add autosave or swipe-to-dismiss behavior.

Make Description visually smaller than SOUL. Use modest rectangular fields with labels outside their borders and a clear focus outline. Allow the SOUL area to use the available height rather than forcing a tall minimum field that pushes the action out of sight.

An uncertain save keeps edits visible and reports that confirmation is missing. A partial save identifies which field was saved and which remains unsaved. Neither state is a success toast. Destructive Discard is visually separated from ordinary Save and uses a distinct semantic color.

Copy refinement for the editor: use "Changes apply to this profile on the server" for scope, and "Guides how Hermes responds in this profile" if SOUL needs helper text. The generated wording must not imply that an unsaved draft is already saved or that SOUL controls the human user's behavior. Diagnostic values in the board are sample states, not observed connection health.

## Basis and remaining work

This pass was checked against the current composer, `ProfileQueuedMessages`, `ProfileActivitySection`, `ChatIntelligenceButton`, administration overview and `ProfileEditorSheet` source. It proposes styling and layout changes while preserving their established interaction contracts. There was no build, device test or application mutation.

Both final boards were visually inspected. The conversation board was corrected to keep the narrow composer dark, reduce ring prominence and remove added Activity timeline dots. The faint guide drawn beside the collapsed Activity header is also illustrative; retain the existing collapsed-header geometry. Exact dp sizes and target boundaries remain governed by the written specification, not inferred from the raster.

Next reviews after feedback on these boards: drawer and connection/profile switching, connection repair, approvals/questions, and reading/output typography. Queued-message editing, active voice capture and extreme text scaling also need explicit specimens before implementation.

## Images and reproducibility

- [Busy conversation and narrow-phone study](images/studio-v3-conversation.png).
- [Administration and profile editor study](images/studio-v3-administration.png).
- [Exact generation prompts](2026-09-14-studio-v3-prompts.md), using the built-in image-generation tool and the previous Studio theme board as a style reference.
- [Targeted conversation correction prompt](2026-09-14-studio-v3-correction-prompt.md) records the dark-composer, ring-size and Activity-decoration correction.
