# Chat model confirmation

When Hermes requires confirmation for a chat model change, Wing shows the
server's warning in a dialog with **Cancel** and **Switch model**. The warning
scrolls independently of the actions, including at enlarged text sizes with
keyboard insets. Cancel, Android Back and tapping outside keep the existing
model and reasoning. Approval applies the selected model first, then reasoning.

The dialog follows Studio's shared theme and control tokens. An inline warning
with actions was considered, but would compete with the transcript and composer;
a modal decision gives the warning focus and keeps both actions reachable.

## Stock desktop and gateway contract

Verified upstream `NousResearch/hermes-agent` main on 20 September 2026 at
`9573f44ca5416022f5c0095580e47b5e23d56e71`:

- [Desktop's shared confirmation](https://github.com/NousResearch/hermes-agent/blob/9573f44ca5416022f5c0095580e47b5e23d56e71/apps/desktop/src/lib/guarded-model-switch.ts)
  displays `confirm_message`, treats dismissal as decline, checks staleness,
  and resends once after approval. A second `confirm_required` is a failure.
- [Desktop's model controls](https://github.com/NousResearch/hermes-agent/blob/9573f44ca5416022f5c0095580e47b5e23d56e71/apps/desktop/src/app/session/hooks/use-model-controls.ts)
  capture the target session and selection when constructing the resend.
- [Gateway model setter](https://github.com/NousResearch/hermes-agent/blob/9573f44ca5416022f5c0095580e47b5e23d56e71/tui_gateway/methods_config_set.py)
  accepts `config.set` with `key: model`, `session_id`, `value` and, on an
  approved resend, `confirm_expensive_model: true`.
- [Gateway selection guard](https://github.com/NousResearch/hermes-agent/blob/9573f44ca5416022f5c0095580e47b5e23d56e71/tui_gateway/model_switch.py)
  returns `confirm_required: true` and `confirm_message` without applying the
  switch. This covers large-context costs and other model selection warnings.

Wing keeps the original profile, runtime, provider, model and `--session` scope
on the approved resend. It never changes the profile default. While awaiting a
decision, duplicate changes and prompt submission are blocked. A changed runtime,
selected chat, profile, model/provider or busy state invalidates approval.
Failed or uncertain resends are not automatically retried. Reasoning remains
unchanged if the model switch is declined or rejected.

Previously the chat controller threw `confirm_message` as an error, leaving the
transcript warning without any way to approve it. The fix is entirely in Wing;
it requires no backend changes or deployment.

## Verification

`test/profile_intelligence_test.dart` exercises the shipped picker through the
controller: unguarded success, approval, decline, stale decisions, duplicate
requests, rejected resends and partial reasoning failure.
`test/chat_model_confirmation_test.dart` checks action reachability and dismissal
at 390 × 844 / normal text and 320 × 640 / 200% text in both themes with a
240 dp keyboard inset. Set `CAPTURE_MODEL_CONFIRMATION=true` to export renders
under `build/model-confirmation-review`, using `build/studio-roboto.ttf`.
These are fixture-based Flutter checks, not live-server or installed-phone evidence.
