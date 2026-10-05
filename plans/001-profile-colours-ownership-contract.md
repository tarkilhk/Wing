# Device profile colour ownership

Profile colours are local to an exact saved connection identity and profile name.
They retain the current SHA-256-scoped key and twelve integer choices; absence
means Automatic. Present malformed values have no selected choice and an explicit
repair notice. These colours remain outside the portable app preference catalogue.

Use the existing AppPreferences storage FIFO. A separate queue cannot protect a
write from SharedPreferences.reload replacing its entire cache. Keep colour
observations in a private module with dedicated per-connection listeners; a colour
save must not notify the general settings, workspace or transcript listeners.
Fresh owner reloads and backup observations refresh registered colour facts.

Both colour views require a route-owned session factory. The session supplies
immutable typed facts, profile membership and a picker lease. Closing/replacing
the session, dismissing its picker or removing the target profile revokes queued
work before the physical write. Already admitted writes finish confirmation or
restoration in the shared owner even when their route retires. UI code arranges
controls and maps domain choices to theme colours; it cannot access preferences,
decode integer choices, infer validity, decide unchanged writes or persist data.

A false or throwing storage acknowledgement restores the prior raw value. Failed
restoration keeps current storage explicitly unverified until fresh reload.
The picker exposes the owner's reload command directly; colour-only uncertainty
must not require an unrelated settings notification to make repair reachable.
Rebinding consumers cannot promote optimistic or unverified plugin cache values
into confirmed facts. A failed reload retains the previous display choice. Known
display facts are retained independently of a currently selectable fact.

Original public regressions cover failed-save selection, repairing malformed
presence with Automatic, replacing a connection while a picker is open, and a
colour write competing with a held shared reload. Retain these behavioral
assertions through the required factory migration. Add owner/lifetime tests for
queued versus admitted writes, profile removal, shared consumer observations,
unconfirmed restoration, notification reentrancy and backup/reload ordering.

Retire the raw store only after resolved production/test caller closure and
register its canonical identity in the retirement guard. Add small deterministic
guards for direct UI persistence and theme-dependent storage validation, with
invalid/valid fixtures, source/compiled CLI proofs and mandatory CI enforcement.
Rendered picker/error states must be inspected in both themes and enlarged text.
This batch does not establish whole-program dead-code or final native acceptance.
