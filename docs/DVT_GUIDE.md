# ARC 2.2.0 external design verification

DVT tests the exact frozen release candidate. It does not complete the product,
waive a requirement, or turn a development build into a release.

The tester must be independent of implementation and must use a clean Apple
silicon Mac running supported macOS. The
candidate manifest binds the tested DMG, complete source archive, and
product-literature PDF by name,
size, and SHA-256.

## Prepare the report

Copy [DVT_REPORT_TEMPLATE.md](DVT_REPORT_TEMPLATE.md) to a plain-text file
outside the checkout. Replace every angle-bracket field. Use short, concrete
evidence such as a test log identifier, screenshot identifier, command result,
or observed state. A blank, skipped, blocked, failed, or unfinished row is not
a pass.

Keep the template's literal first line `ARC 1.0 EXTERNAL DVT REPORT` and
`arc.dvt/1` schema: those are the existing parser's report-format identifiers,
not the product version. Its version/tag fields identify ARC 2.2.0. Do not
relabel the wire format or reuse an older candidate's PASS evidence.

Run `make release-dvt DVT_REPORT=/absolute/report.txt` after completing the
tests. The check accepts only the exact template shape, all 15 PASS rows, a
named tester and independence statement, UTC start and finish, identified
machine, system, and toolchain, the DMG/source/manifest hashes, no
deviation, and the final PASS decision.

## Required tests

### DVT-001-SOURCE

Extract the complete source archive into a new directory. Confirm it contains
the Swift package, shared core, app, command, C knowledge reader, developer
tool, tests, specifications, user and developer documentation, editable artwork,
app icon, brand assets, CI, release procedure, man page, and legal files. Confirm
there are no links, build products, room data, credentials, caches, or unknown
binary dependencies.

In the extracted tree, `make source-archive-test` must fail closed because the
published archive has no Git metadata. That refusal is required evidence; a
zero exit is a DVT failure. Rebuild and run the remaining `make check` targets
from the extracted tree without network access. Separately, from a Git
checkout of the same tagged revision, run `make source-archive-test` and
confirm it passes (generated archive modes 0644/0755, no group/other write).

### DVT-002-NATIVE-BUILD

Run `make app-release-check`. Confirm ARC.app and its installed `arc` command
are arm64-only. Confirm the bundle has no private helper,
downloaded code, alternate command implementation, or non-system framework.

### DVT-003-INSTALL

Install the DMG by dragging ARC to Applications and opening it without Terminal,
administrator privilege, or a package manager. Confirm first launch publishes
only the verified native command, knowledge, specifications, legal text, and
receipt under Application Support. Relaunch, repair, and upgrade from a prior
valid receipt. Confirm an unknown collision or linked parent is refused and
existing rooms are untouched. Repeat with hostile `PATH`, `HOME`, ARC-named
environment variables, and a read-only destination. Exercise every documented
installer interruption boundary and reopen after each stop.

Verify the complete tracked Terse v1.0 file, its SHA-256 sidecar, and
every plain-text ARC specification against the signed manifest. Test a clean
2.2 installation and upgrades from verified 1.1 and 2.0 installations; retain rooms
and the operator-language preference on upgrade.

### DVT-004-FIRST-ROOM

As a new user, create and name a room. Confirm the friendly name and generated,
read-only Room ID are both visible. Confirm the first useful action is obvious,
the AI name field and Copy AI Instructions to Paste Buffer button are
understandable. Confirm the sentence beneath them says exactly `Paste the
instructions directly to the AI Chat you are using for that AI Name.` Raw
identifiers do not dominate the screen, and the Administrator is never
described as a participant or Producer.
Quit immediately after creating the room, reopen ARC, and confirm the same
friendly name, fixed Room ID, and empty-room next action return.

### DVT-005-TWO-AI-ACTIVE

Invite two AIs through separate existing chat sessions. Follow the copied
instructions exactly. Confirm the first qualified AI becomes Producer, both
qualified AIs become On Duty, and only then does the room say Active. Add a
third AI to prove that two is a minimum rather than a fixed participant count.

### DVT-006-QUALIFICATION-FAILURE

Exercise the fixed qualification check. For a later AI, have the Producer start
it, then delay that AI's first poll by 0, 20, 39, 41, 79, and 81 seconds in
separate test rooms. Each first poll must return its challenge and a complete
40-second finishing window; none may inherit a deadline from Producer start.
Advance the event cursor past the start event and confirm the challenge remains
available in poll output. Make the Producer Off Duty while another AI is still
On Duty and confirm a candidate poll starts the same check without Administrator
intervention. Withhold or give an incorrect answer and prove the AI becomes
failed only after its deadline. Confirm the next own poll starts a fresh challenge,
up to two automatic retries; room refreshes and other AI polls do not consume the
retry budget. Exhaust both and verify clear inline guidance and the prominent
Reconnect AI & Copy Instructions button. Paste into the same chat and complete
the fresh check. Confirm history/binding preservation and clipboard failure handling.
Inspect narrow/wide windows, light/dark appearance and VoiceOver labels.

Complete a VISUAL item using an actual inspection timestamp. Refuse pre-creation,
future, malformed and placeholder times without consuming the operation token.
Correct evidence with work.correct, verify both revisions remain in history,
replay without duplication, refuse another owner's/stale-revision correction,
then reopen through Producer reassignment. Test the 50-current-item limit.
Legacy completed evidence must remain readable, including a known-bad timestamp.

The initial handoff must name the full local Terse file and require reading
every section and appendix, starting with section 19. Test the version exchange,
digest verification and changed-digest reread. Unavailable communication
guidance must not be described as proof that an AI read or understood Terse.

### DVT-007-PRODUCER-CHANGE

Choose another qualified AI as Producer several times. Confirm the visible
Producer and generation change together. Make the Producer Off Duty and confirm
the room stops saying Active until a live Producer is chosen or returns.

### DVT-008-REPLACE-AND-RETIRE

For a healthy AI, use Replace Instructions and confirm the old binding is
invalid immediately. For an Off Duty AI, use Copy Instructions Again and confirm
the binding does not change; a valid later poll returns it On Duty. Retire an AI
at several lifecycle points. Confirm retired bindings never work again.

### DVT-009-MESSAGES-AND-WORK

Send directed messages and confirm only the intended AI receives each message.
Assign, update, block, complete, and reassign work using operation and
revision controls. Complete both text evidence and a visually verified result.
Confirm stale or conflicting mutations are rejected without partial change.

Send a room-wide notice to qualified On Duty, Working, and Off Duty peers.
Verify identical addressed copies, no sender/unqualified/retired copy, exact
retry without duplication, and capacity refusal without partial delivery.
Use actual characters such as Größe, Füße, geprüft, ä, ö, ü, and ß.
Test an invalid visual timestamp: the refusal must name inspected_at and its
six-fractional-digit UTC form; correct it using the unconsumed current token.
Distinguish an independent qualification-expiry event from a partial action.

Run the current acceptance cases in [ARC_2_1_TEST_REVIEW.md](ARC_2_1_TEST_REVIEW.md),
including the retained language cases:
explicit THIS focus and repair, FILE with its path, same-turn vocabulary
declaration on specification offers, valid utterance references, and no
redundant bilingual/prose restatement. Label intentionally invalid traffic and
do not claim ARC enforces Terse syntax.
Confirm `spec list` includes 013 and `spec read 013` returns the complete
installed Terse v1.0 text. Verify integer handshake 1 and full-file digest.
For any necessary prose fallback, require the sending AI to choose one language
for that concept. A Producer must not impose English/German or demand parallel
translations. Handshake inconvenience alone does not justify prose fallback.

### DVT-010-POLLING-RECOVERY

Use an AI chat with a roughly once-per-minute wake-up. Confirm the handoff
pasted into the chat itself says to arrange a later poll about once a minute
and warns that missed check-ins become Off Duty. Confirm the full guide says
ARC does not wake chats. Stop polling until the AI becomes Off Duty, then poll
again and confirm it returns On Duty. Confirm Room History is newest-first,
separately scrollable, and complete from the first room event.

Declare Working before pausing polls; extend its deadline strictly later
before expiry; reject an earlier extension; verify exact-deadline Off Duty,
normal-poll return, and restart behavior. Working counts as available without
claiming the AI is polling or immediately responsive.

Open the separate Room Activity window, change the selected room, and verify
history never mixes rooms. Test Follow Live on/off, incoming updates while
covered, older-history paging, inert selectable text, Find, and close/reopen.
The viewer must not send messages or enable room mutations while focused.

### DVT-011-ROOM-INTEGRITY

Inspect one room as human-readable canonical JSON. Exercise simultaneous reads
and mutations, a five-second lock timeout, interrupted temporary writes, and a
relaunch. Confirm one stable adjacent lock, atomic updates, monotonic revisions
and sequence numbers, strict format rejection, an 8 MiB room limit, complete
Activity from sequence 1, fail-closed over-limit writes, and no state in the
lock file. Confirm malformed, linked, busy, and over-limit rooms receive the
correct diagnosis without mutation. Exercise every installer interruption
boundary and a read-only destination.

### DVT-012-PRIVACY-AND-OFFLINE

Run with network access disabled. Confirm all ordinary behavior still works,
no network request is attempted, no analytics or tracking data is emitted, and
room contents remain in the Administrator's account. Retire every AI, then
permanently delete one room and confirm its history and lock are gone while
unrelated rooms and installed files remain unchanged.

Separately test an older room too full to record all retirements. Confirm
deletion recovery is offered only under DS-011, explicitly warns about ending
remaining lanes without retirement records, and refuses On Duty/Working AIs,
live qualification, or unusable time. A normal inactive room with enough
capacity still requires retirement.

### DVT-013-ACCESSIBILITY

Complete first use and normal room operation using keyboard navigation and
VoiceOver. Check focus order, labels, status announcements, contrast, text
scaling, reduced motion, and that color is not the only status signal.

Include the read-only activity viewer at 520 by 360 points and main window at
900 by 650. Confirm participant colors and event labels remain distinguishable
without relying on color alone. Test English/Deutsch selection and persistence,
failed preference saves, updated poll guidance, and unchanged original history
text. The selector does not translate menus or peer messages.

### DVT-014-AGE-14-USABILITY

Give the signed build and the short Getting Started page to a first-time tester
age 14 or older. Without coaching, ask the tester to create a room, invite two
AIs, identify the Producer, explain On Duty versus Active, replace instructions,
retire an AI, diagnose a room, and find privacy/help. Record misunderstandings;
any required task the tester cannot complete is a failure.

### DVT-015-SIGNING-NOTARIZATION

Verify the Developer ID signature, hardened runtime, bundle identity, privacy
manifest, notarization, and staples for ARC.app and the DMG. Confirm the DMG
contains only ARC.app and the Applications link. Compare the DMG and source
archive and product-literature PDF with the candidate manifest before recording
PASS.
