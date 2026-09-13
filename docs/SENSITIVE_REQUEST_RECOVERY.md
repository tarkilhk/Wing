# Recovering pending sensitive requests

Owner correction, 2026-09-12: **No Hermes backend modifications.** Any patch
contracts or deployment instructions described below are rejected experiments,
retained only as research. They were never deployed. Use existing Hermes APIs;
features requiring those invented contracts are deferred, not delivered. Do not
configure a new Hermes sender or deploy patches based on this document.

## Current behavior

D07/R08/R09 handle live sudo, environment-secret and vault requests through
the server's existing request/response events. Android checks the request's
identity before submitting and clears matching expired or answered forms.
Entered values remain in memory, outside drafts and conversation storage.

Cold or cross-client recovery is deferred. No pending-sensitive snapshot has
been verified on unmodified Hermes. The client can parse `pending_sensitive`
if supplied, but that parser does not make the server capability available.
Live acceptance and environment limits are recorded in
[the remaining QA cases](QA_REMAINING_ACCEPTANCE_2026-09-14.md).

## Historical proposal, rejected and never deployed

The following describes the 2026-09-12 proposal, not delivered backend behavior.

The Android client reads `pending_sensitive` from session resume responses and
session-info updates. An explicit null clears an expired or answered request.
An update without this field leaves the live question intact. A replacement
request clears the previous form's entered value; the same request keeps its
current in-memory input. These values never enter draft or conversation storage.

The [backend patch](../server-patches/0004-sensitive-prompt-recovery.patch)
exposes the server's existing pending-request registry. It requires the exact
runtime owner, an unanswered request and an unexpired monotonic deadline.
The envelope contains only the request type, request ID and allowlisted display
metadata. Passwords, supplied answers, commands and arbitrary metadata are
excluded. No new credentials database is introduced.

Supported types are sudo password, skill/environment secret, vault unlock,
vault save-login and vault verification code. The client reuses the existing
dedicated response methods and checks the original request before submitting.
If the server says the request no longer exists, its form is cleared.

This contract needs patch 0004 on the backend. A cold server session or server
restart cannot recover an in-memory request that no longer exists. Compute-host
isolation currently mirrors only clarification requests and cannot restore
sensitive prompts through this contract. The client does not invent a prompt
or cache an answer to cover either limitation.

The focused Android checks cover all five request families, explicit null,
partial updates, malformed metadata, ownership, status and form replacement.
The backend checks include expiry, answered requests, live/cold resume, lazy
session-info emission and the existing protocol suite. Full release validation
and deployment status are recorded in the [changelog](../CHANGELOG.md) and
[delivery sequence](DELIVERY_SEQUENCE.md).
