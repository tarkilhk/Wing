# One-chat Hermes notification test

**22 September update:** the five selected live runs are finished; see the
[retest results](2026-09-22-notification-retest-results.md) and
[current status](2026-09-20-notification-test-status.md). Build **2327** is installed
with fixes for the partial/failed cases. Sound is confirmed. Do not rerun the
whole suite: use the [two focused retests](2026-09-22-notification-followup-retests.md)
for initial unopened-chat input content and unread-reply restoration/read clearing
after force-stop. New activity/full-bottom remains a separate UX follow-up. For
future desktop decisions, give an explicit **NOW: select Summary on desktop**
cue in the conversation as well as any question card, and account for the stock
request's observed five-minute timeout.

Paste the entire code block below into one new Hermes chat in Wing. Open **that
same chat** on desktop if possible so you can send controls without reading the
answer in Wing. Reply `RUN 01`, then advance through the scenarios when ready.
Hermes must wait for your observations; it cannot see Android's notification shade.

**Before each new desktop-triggered background test**, open Wing on the owning
connection's chat list, without opening the test conversation. Send the control
from desktop, confirm Wing's **Watching…** notification appears during the tool
wait, then background Wing before the answer finishes. Monitoring stops when
known work ends: an unread notification does not keep it running. Staying
backgrounded between separate desktop turns does not establish delivery.
If Watching never appears, record a monitoring/delivery prerequisite failure;
do not call it a notification-text replacement failure.

Install the notification-revamp Wing build first. Enable Wing's reply and
attention notifications and allow their Android channels. Start with previews
on and normal text size. Do not change your usual battery settings for the first
run. This is a guided test prompt, not a command to modify Hermes configuration.
For repeated desktop turns after an idle reconnect, use build 2325 or later;
the [live test record](2026-09-20-notification-live-results.md) documents the
loaded-chat subscription failure found in build 2323 and its recovery fix.

```text
Help me manually test Wing's Android notifications using this ONE chat.
Act as a test driver, using your actual available Hermes tools. Do not just
write a story describing notifications. Keep each response brief and useful.

CONTROL AND EVIDENCE
- First inspect available tool schemas and relevant approval capabilities
  read-only. Tell me which scenarios you can genuinely generate, then wait.
- I control progression with RUN <number>, REPEAT <number>, SKIP <number>,
  OBSERVED <number> <my observations>, and REPORT. Never run the whole suite
  automatically. Before an unfamiliar test, state my setup and expected result;
  wait for GO before creating the event. For every desktop-triggered background
  round, including NEXT B and NEXT C, use a bounded 20-second tool wait before
  producing the tested event. I first open Wing on the owning connection's chat
  list, send the control from desktop, check Watching appears, then background
  Wing. Do not assume an unread notice keeps monitoring active between turns.
  If I report no Watching notification, record that prerequisite failure and
  pause the scenario; do not assert that content replacement was exercised.
- Do not use the structured question tool for test administration. Reserve it
  for scenarios explicitly testing real questions. Otherwise use normal chat.
- Label test content WING-N01, WING-N02, etc. Make each reply's opening sentence
  say what happened and what I should do next. No reasoning dumps or filler.
- A completed tool operation is not proof that a notification appeared. Record
  backend outcome separately from what I report observing on Android.
- Use PASS only when the required action succeeded AND I confirmed the relevant
  UI observation. Otherwise record FAIL, BLOCKED, NOT OBSERVED, or SKIPPED.
- Stay in this chat. Do not create other chats, scheduled jobs, or child-agent
  conversations. Do not install plugins, patch Hermes, fabricate gateway
  events, call private implementation functions, or impersonate a UI client.
- If a real request cannot be produced with exposed stock tools, mark that
  scenario BLOCKED and explain the specific limitation. A sentence asking
  'May I?' is not a backend approval; a normal question is not secure input.

SAFE TEST OPERATIONS
- Use only harmless print/sleep operations and disposable test files. Keep
  waits finite: normally 20 seconds, at most 90 seconds of work per run.
  Use waits, not CPU-intensive loops. No detached processes or persistent jobs.
- If approval tests need filesystem work, create a fresh OS temporary directory
  with a unique wing-notification-test- prefix. Operate only on children created
  by this run; verify the exact paths and never follow symlinks. No real user
  files, network transfers, credentials, package installs, or system changes.
- Prefer an exposed stock approval-capable tool with a harmless payload. If
  normal command approval is the only route on POSIX, a possible bounded probe
  is deleting ONE explicitly verified test child with
  rm -rf -- '<absolute fresh test child path>'. Never target the parent temp
  directory, use wildcards, or substitute a user/project/home directory.
  On other operating systems use only a verified equivalent, or mark blocked.
- Approval policy may auto-allow that probe. Inspect the policy read-only if
  possible. Do not change approval modes, permissions, allowlists, timeouts,
  credentials, or server configuration. If no request appears, report that;
  do not escalate to a more dangerous command to force one.
- Never retry a denied operation or reinterpret denial as permission.
- Leave Session and Always tests until the end: granted patterns can suppress
  later approvals. Do not revoke unrelated rules to make tests pass.
- Never ask for real secrets. A secure-input test, if genuinely supported, uses
  a dummy value I enter myself, which you must not repeat in replies or logs.

SCENARIOS (only run the one I select)

01 — Reply and reading
  After GO and a short delay, finish with exactly:
  'WING-N01: The sample report is ready. Open this chat and read the result.'
  I leave Wing before completion. Expected: one reply notification with that
  useful content and a normal wing icon. Tapping opens this chat at its latest
  available reply and clears that result once it is visible. On a repeat I
  first open older history: merely entering the chat must not clear it until
  I reach the latest answer. I report whether that distinction was observable.

02 — Replacement and identical replies
  Run this in three separately controlled rounds, commanded from desktop.
  Before EACH round I reopen Wing's owning connection chat list, leaving the
  conversation unread. While your 20-second tool wait runs, I check Watching
  appears, then background Wing before completion. Round A produces a short
  sample result labelled A.
  Round B produces a different result labelled B. Do not start B until I say
  NEXT B. Expected: B replaces A in the SAME chat notification slot.
  After NEXT C, complete another genuine turn with exactly the same final text
  as B. Expected: this is a new reply event even though its words are identical.
  Do not claim exact historic-message navigation: when Hermes supplies no
  stable answer ID, Wing deliberately opens the latest available reply.
  Do not send NEXT B or NEXT C with Wing already idle in the background and
  assume delivery. If reopening Wing reads/clears the prior result, repeat with
  Wing outside the conversation; that run cannot prove replacement either.

03 — Foreground behavior
  I keep this chat visible for a normal short reply: no new completion alert
  should interrupt me. Separately, create a real approval or structured
  question while the chat is visible: attention notifications remain allowed.
  Record both observations, not just the final reply.

04 — Ongoing monitoring and interruption
  Perform one harmless bounded 60-second task in this chat. Let me leave Wing,
  inspect monitoring, lock the phone, and wait for the result. Expected: the
  approved wing/circular-arrows icon and a truthful live 'Watching…' summary,
  then a reply notification after completion. Repeating this test, I press
  Stop during execution to exercise an actual interrupted turn. Do not call
  an ordinary tool exit-code failure a failed or interrupted assistant turn.
  Confirm monitoring stops when no qualifying work remains; pending input
  alone must not keep it running. One chat cannot validate multi-chat counts.

05 — A real batch of three questions
  Use the stock structured clarification tool, if available, for ONE batch of
  three independent questions: environment (Preview/Production), color
  (Blue/Green), and output (Summary/Checklist). Use its actual supported schema.
  Expected: real input notification, useful question/choice text, a Review
  action opening this chat's question, and counts of unanswered decisions.
  I answer one at a time and inspect updates. Then give a short final result.

06 — Approve once
  Request approval for one harmless test operation. I inspect the actual
  command and tap Once in its notification. Expected: only that request is
  accepted; the notification stays during submission and advances/clears only
  after backend confirmation. Report the actual tool outcome afterward.

07 — Deny
  Request a new harmless test operation, then wait for my notification Deny.
  Expected: that request is denied without execution or an automatic retry.
  Verify the test artifact still exists if deletion was the probe. Give a
  short factual outcome. Do not submit another variant of the denied action.

08 — FIFO approval queue
  If your runtime supports concurrent tool calls in this same chat, issue THREE
  separate approval-bearing operations in one parallel batch, with distinct
  verified test targets Q1, Q2, Q3. Do not combine them into one shell command.
  Backend arrival order, as observed in Wing, defines FIFO; labels alone do not.
  I inspect the head and total, approve one with Once, deny the next, and approve
  the last with Once. Each tap must address that displayed request, advance in
  order, and leave the others unresolved. New requests/advancement should request
  sound, subject to Android settings; unchanged/status-only refreshes stay quiet.
  If execution serializes and only one request can be outstanding, mark the
  concurrent queue case BLOCKED; sequential prompts do not prove FIFO queuing.

09 — Mixed input priority
  Only if stock same-chat concurrency permits, leave an approval unresolved,
  then create a real question, and let an independent same-chat task complete.
  Expected: oldest unresolved input remains represented ahead of the newer
  answer; grouped counts are accurate. After all input resolves, the latest
  unread result appears unless I already read it in Wing. No new chat or child
  conversation to manufacture this case. Mark unsupported combinations blocked.

10 — Swipe dismissal
  Create a request that I leave unresolved and swipe away. Keep it pending.
  Ordinary refresh/reconnect must not bring the unchanged notification back.
  If the runtime can add another request without resolving the first, do so
  only after my NEW REQUEST instruction: that genuinely new request should
  restore the alert while preserving the oldest unresolved request as head.
  If a blocked tool call prevents further dispatch, record the second half as
  not covered. A later final reply does not prove that pending-input case.

11 — Long command and visual inspection
  Request one safe operation whose genuine command is long enough to truncate,
  using a long but valid test-child name (keep each path component below the OS
  limit). Do not add risky options or a deceptive description just for length.
  I inspect collapsed/expanded views, light/dark themes, and 200% text. Show only
  backend-offered choices. At large text, four choices should use two rows.
  If I cannot review the full command in the notification, tapping a choice
  should open this chat for review/confirmation before execution. I may cancel.
  Shorten the command for other tests; do not assume every tap is a direct grant.

12 — Hidden previews and channels
  Wait while I disable Wing message previews, then create a fresh real input.
  Expected: private command/question text and direct approval choices are hidden;
  Review opens this chat. Repeat with previews restored.
  Separately I disable an Android notification category, inspect Wing's blocked
  category notice/settings link, then re-enable it. Generate the corresponding
  event on request. Absence while blocked is expected, not a backend failure.

13 — Device unlocking
  Create an approval, then wait while I lock my phone and inspect the notice.
  No approval or denial may reach the backend without authentication. If Android
  exposes an action, I try it and cancel unlocking: no decision should execute
  or replay later merely because the app reconnects. I then unlock normally
  and explicitly retry. Do not change my phone's PIN or lock-screen settings.

14 — Offline action and stale request
  Create an approval. I disconnect ONLY Wing/the phone from the backend and
  try its notification action. Expected: no false success or silent clearing
  on a failed attempt, no deferred automatic grant on reconnection. I restore
  connectivity, review current state, and explicitly retry if still pending.
  On a separate repeat, I resolve the request on desktop and then try any stale
  notification action still present. It must never act on the next request.
  Record actual acceptance separately from ambiguous/time-out outcomes.

15 — Desktop resolution and watcher lifetime
  Create a pending request for me to resolve in this SAME chat on desktop.
  I first check whether Wing's existing monitoring watcher is actually running.
  If it is, expect reconciliation to advance/clear the request within roughly
  one 30-second polling interval plus network time. Do not assert a hard deadline
  during Android sleep restrictions or lost connectivity.
  If this chat is only waiting and the watcher has stopped, stale background
  state is allowed until normal Wing resume/reconnect: test that path instead.
  Do not keep monitoring alive just for this test or create a second chat.
  Only if genuine independent same-chat work can keep it running may we test
  watcher-active polling here; otherwise mark that branch not covered.
  Opening/reading this chat on desktop alone MUST NOT clear Wing's reply notice:
  stock desktop read state does not establish latest-answer visibility.

16 — Restart, reconnect, and stopped work
  Produce a reply I leave unread. I close/reopen Wing and inspect its target and
  read clearing. Repeat with pending input and a dismissed notification.
  App opening must not count as reading; stale actions must not target a new
  request. Do not confuse swiping the recent-app card with a guaranteed process
  death. An explicit Android Force stop interrupts monitoring until app relaunch;
  no notification delivery is expected while force-stopped.
  A genuine assistant-turn failure may be tested only if exposed stock controls
  support a harmless reproducible one. Do not break credentials, stop the server,
  or fake a failure by writing 'ERROR' or issuing a failing shell command.

17 — Secure input, if genuinely available
  Use an exposed stock secure-input flow only if it can safely accept dummy test
  data without changing an account or saved credential. Tell me its actual
  capability first. Expected: generic secure-input notification, Review into
  the owning chat's secure UI, no dummy value in the notification or final text.
  Otherwise mark BLOCKED. Do not substitute a plain-text clarification question.

18 — Session scope (run after other approval tests)
  If offered, request a harmless test operation. I inspect the backend's actual
  matching scope and tap Session. Report acceptance and actual outcome. A
  repeated matching test operation may legitimately skip approval afterward;
  distinguish that backend rule from a missing Wing notification. Stay in this
  chat. Cross-session isolation cannot be proved in this one-chat run.

19 — Always scope (last, explicitly controlled)
  If offered, request a harmless test operation. I tap Always, inspect its
  permanent-pattern explanation in Wing, and cancel. No decision should execute.
  Only if I later type APPLY ALWAYS and the actual backend pattern is narrowly
  confined to disposable test operations should we test successful permanent
  acceptance. Do not infer narrow scope from a safe-looking example command.
  If scope is broad/unknown, stop at confirmation/cancellation and record that
  permanent acceptance was not tested. Record any rule I explicitly accept so
  it can be reviewed afterward; do not edit allowlists or remove unrelated rules.

REPORT AND CLEANUP
On REPORT, produce a compact table: scenario, backend event/tool evidence,
my Android observation, PASS/FAIL/BLOCKED/NOT OBSERVED/SKIPPED, and next step.
List created test paths and any still-pending requests. Offer to remove ONLY
this run's disposable artifacts, using normal approvals; don't silently clean
up pending test operations or undo a permanent grant through private APIs.
Explicitly list what this one-chat test cannot prove: isolation between chats,
connections/profiles, multi-chat monitoring counts, cross-session/permanent-rule
persistence, arbitrary backend permission flags, guaranteed request expiry or
turn-failure injection, unavailable secure-input flows, and any concurrency or
watcher-active polling branch that the runtime could not generate.
Start with the capability check and wait for RUN 01.
```

Contract references checked when preparing this prompt:

- [Stock approval gate and queue](https://github.com/NousResearch/hermes-agent/blob/main/tools/approval.py)
- [Stock structured clarification tool](https://github.com/NousResearch/hermes-agent/blob/main/tools/clarify_tool.py)

The prompt asks Hermes to inspect its own exposed schemas rather than treating
internal Python helpers as model-callable tools. The scenarios are a test plan,
not a claim that the installed backend can generate every condition on demand.

### Round 2 field correction

The first phone run retained the setup notification after A and B completed on
desktop. The user did not observe Watching, and a subsequent read-only device
check found no Wing monitoring service. This is consistent with the documented
idle monitoring lifetime; a receipt trace of the original turns was not captured.
The original prompt incorrectly assumed continuous delivery between backgrounded
desktop turns. The per-round monitoring prerequisite above corrects that test.

Subsequent controlled LIVE-4 testing also reproduced a client bug **with Wing
foregrounded**: after idle reconnect, loaded chats were excluded from working
snapshots without reattaching their event subscription. Build 2325 repairs that
path. The monitoring prerequisite alone did not fix the older build; see the
linked live results for the failing and fixed-run evidence.

Focused checks pass (26 tests): stock start/completion sequences preserve setup,
A, B and an identical C reply; the coordinator updates both compact and expanded
text in the same notification slot; monitoring ends after known work finishes.
A completion-only synthetic sequence initially failed because it omitted the
start event. Stock [`prompt_turn.py`](https://github.com/NousResearch/hermes-agent/blob/2ed6387d87b4db091af2f05db32faab6e0dbb9a2/tui_gateway/prompt_turn.py)
was verified at `2ed6387d87b4db091af2f05db32faab6e0dbb9a2`; adding that real event
made the fixture pass without changing production code. These checks do not
establish receipt of the original phone events. Retry with Watching observed
before attributing a remaining failure to replacement or delivery logic.


## Build 2326 bug-fix retests — run first next session

These are required live regressions for the two bugs fixed after tonight's tests.
They revisit scenarios 05, 10, 15 and 16; they are not extra scenarios in the
19-scenario count. These instructions were exercised on 22 September; consult
the linked results for passes, partial coverage, timeouts and remaining gaps.
The user drives the same Hermes desktop chat; Codex operates Wing and records
Android state. No approval-policy changes are needed.

### R1 — Remaining question count (scenario 05)

Open Wing's connected chat list with previews enabled. Send this on desktop:

```text
WING-RETEST-COUNT: Use a terminal tool to sleep for 20 seconds, then use
one real stock structured clarification batch containing three questions:
environment (Preview/Production), color (Blue/Green), and output
(Summary/Checklist). Use your exposed tool's actual schema. Wait for my answers;
do not substitute ordinary chat questions or answer yourself. After all three
are answered, reply briefly with the three selected values. If the real batch
is unavailable, report BLOCKED instead.
```

1. Confirm Watching starts, then background Wing before the batch arrives.
2. Inspect collapsed and expanded notifications: both must display **3 questions**
   and useful first-question text, with Review opening the correct chat/form.
3. Answer Preview in Wing, inspect the shade: **2 questions**, next question text.
   Answer Blue, inspect again: **1 question**, final question text. There must
   remain only one notification slot for this chat.
4. While the last question is pending, turn previews off. Its count must remain,
   but question/choice text must be hidden. Restore previews before continuing.
5. Answer Summary. The resolved-input notice must advance/clear; no old question
   or count may remain. A later unread result may occupy the same slot.

Record each actual count and any clipped text; do not infer counts from Wing's
in-chat “1 of 3” form. Restore previews if the run is interrupted.

### R2 — Dismissed question, restart, desktop resolution (scenarios 10/15/16)

Open Wing's connected chat list. Send on desktop:

```text
WING-RETEST-STALE: Sleep for 20 seconds using a terminal tool, then ask one
real structured clarification question: "WING-RETEST-STALE: Which output
should I prepare?" with Summary and Checklist. Keep it pending until I answer.
After my answer, reply briefly with the selected output and do not create any
further request. If the structured tool is unavailable, report BLOCKED.
```

1. Confirm Watching, background Wing, and capture the pending question notice.
2. Swipe away that notice. Reopen only the connected chat list: Needs input is
   correct while the question is unanswered; the dismissed notice must stay gone.
3. Explicitly force-stop and relaunch Wing, then return to that chat list. Confirm
   the still-pending state and retained dismissal. Do not expect delivery while
   force-stopped; complete relaunch/reconnection before the next step.
4. Ask the user to answer Summary **on desktop** and let Hermes finish, while
   Wing remains connected on the chat list. Record when it loses Needs input.
   Do not open the chat, visit Settings, or manually refresh to make it pass.
5. Background and resume to the chat list once more. It must remain Idle, with
   no old question resurrected. Finally open the chat to verify the completed
   answer and absence of a question form, then return: the badge must still be Idle.

Pass requires the actual list status to clear, including its cached activity
state. A completed answer visible inside the chat alone is insufficient—the
original bug persisted in the list even after that check. A fresh completion
notification is allowed; it is not resurrection of the dismissed input notice.

### R2b — Visible request resolves while work continues (scenario 15)

Repeat R2's prompt with label `WING-RETEST-CONTINUE`, adding this instruction:
“After I answer the question, use a terminal tool to sleep for 30 seconds before
your final reply.” Start from the connected Wing chat list, observe Watching,
then background Wing for the question. Keep its notification visible this time.

When the question is ready, return only to Wing's connected chat list, then have
the user answer on desktop. While Hermes continues the 30-second wait, verify
Needs input clears to Working and monitoring starts. Background Wing once it
starts. The old question/choices must disappear; the final answer must arrive
and monitoring must end. Never require a lone waiting question to keep watching.

If any variant lacks a required backend event or reconnect, record the observed
state and prerequisite failure. Do not mark it passed because unit tests passed.
After these retests, continue only the outstanding items in the clean status;
do not rerun blocked approval probes without a new safe way to produce them.
