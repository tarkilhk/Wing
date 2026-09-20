# Wing

Wing lets a user work with Hermes chats across connections and profiles. This
glossary records the domain language agreed during product design.

## Language

### Notifications

**Chat notification**:
A user-facing notice about one chat's latest relevant state, including a result
to read or a request to answer.
_Avoid_: Turn notification when referring to the notice for the whole chat.

**Latest relevant state**:
The chat state that currently deserves the user's attention; unresolved input
takes precedence over a newer result.
_Avoid_: Latest event as a synonym.

**Pending input**:
An unresolved request for the user's answer, approval, or secure input.
_Avoid_: Approval when the request may instead be a question or secure input.

**Approval request**:
A request for permission to perform an operation, with the permission scopes
offered by Hermes for that request.
_Avoid_: Notification action as a synonym for the request itself.

**Approval queue**:
The outstanding approval requests belonging to a chat.
_Avoid_: Batch approval, which suggests one decision for every request.

**Pending-input queue**:
A chat's unresolved approvals, questions, and secure-input requests in the order
Wing first learned of them, with the oldest unresolved input first.
_Avoid_: Approval queue when including other kinds of input.

**Read result**:
An answer the user has reached in its Wing chat, without needing to read every line.
_Avoid_: Opened chat as a synonym for having reached its answer.

**Pending decision count**:
The number of unanswered user decisions, grouped by kind; a form containing
three unanswered questions contributes three questions.
_Avoid_: Request count when counting individual questions within a form.

**Accepted approval decision**:
A permission choice Hermes has acknowledged accepting for an approval request.
_Avoid_: Successful command, which describes the subsequent execution outcome.

**Approval scope**:
The extent of an authorization: once, the current session, or a permanent rule
for the applicable command pattern.
_Avoid_: Approve all as a synonym for session or permanent permission.

**Notification dismissal**:
The user's removal of a notice without answering, denying, or resolving the
underlying request.
_Avoid_: Denial, cancellation, resolution.

**Monitoring notification**:
The ongoing notice describing the work Wing is currently watching across chats.
_Avoid_: Chat notification, which concerns an individual chat's state.
