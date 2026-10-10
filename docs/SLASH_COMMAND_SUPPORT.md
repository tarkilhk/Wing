# Slash commands and skills

Type `/` at the start of the composer to browse the connected server's commands,
plugins, and installed skills. Type `/` after a space or on a new line within a
message to browse skills. Search matches names, aliases, and descriptions.
Selecting a result replaces the slash token at the cursor and keeps surrounding
text. Skill references remain editable and copy as ordinary text. URLs and paths
stay literal. Refresh the workspace after changing installed skills.

On Send, Wing loads referenced skills before submitting the message. The chat
shows your original wording. Repeated references to one skill load it once;
different skills can be combined. If loading fails, the queued message is
retained rather than sent without its instructions.

Some commands start a response; others return output or place text in the
composer for editing. Display-only command output is not saved in model history
and leaves composer attachments in place. A failed or timed-out command is not
automatically sent through another handler: check its result before retrying.

`/yolo` changes the current chat's setting and shows the confirmed state; it does
not change global defaults. `/steer`, interruption, status, and side questions
can address active work. Commands that start a normal turn wait until idle.
Built-in commands mentioned within ordinary prose remain text.

A command's presence in the catalog does not guarantee it works on mobile.
Terminal-only and messaging-only commands retain their requirements. A server
microphone command does not use your phone's microphone. You can still type a
command by name when the catalog is stale.

Skill receipts open the [instruction reader](TOOL_ACTIVITY.md#captured-skill-reading)
without rerunning the command. See [Queues and pending input](SUPERVISION_AND_QUEUES.md)
for side-question recovery limits.
