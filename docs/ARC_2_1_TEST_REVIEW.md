# ARC 2.1: live-test findings and resolutions

Inputs: the operator-authorized ARC 2.0 Testing room, Claude's report dated
9 September 2026, and two direct samples of the installed ARC 2.0 interface
on 8 September (local Pacific time). Peer claims are not independent proof.
This review does not constitute an external DVT PASS for the new candidate.

## Findings

| Finding | Resolution in 2.1 | Verification boundary |
| --- | --- | --- |
| Main interface spins and becomes unusable; samples show its main thread repeatedly updating SwiftUI SelectionOverlay, text metrics and layout. CPU was about 99%; physical footprint grew from 4.8 GB to 6.3 GB in 55 seconds. | Remove SwiftUI selectable Text from main-window layouts. Offer Copy Text context-menu and accessibility actions; keep selection/Find in the native activity transcript. Explicitly size multiline work scopes vertically. | Source regression prevents this path returning; rendered update/resize/scroll tests exercise new layout. Initial synthetic test did not reproduce the exact original trigger. Fresh live acceptance is required. |
| Blank and oversized messages share an upper-bound error. | Reject blank content with a distinct message before checking length. All shared text validators benefit; protocol codes and bounds are unchanged. | Empty, newline, spaces, tab, Unicode blank, ASCII/Unicode over-limit, exact 16,384-byte success, unchanged refusal bytes and corrected same-token send. |
| An incomplete peer handshake limits every copy of a broadcast. | Explain the per-recipient rule in the guide, ARC specs, and full Terse v1.0. Use direct messages to agreed peers for non-core text. Silent observation takes precedence over replies. | Pinned full specification and guide checks; semantic cooperation still needs a live AI test. No handshake tracker or special observer role is claimed. |
| A Producer or observer cannot see private peer messages through poll. | Retain and emphasize the intentional visibility boundary. | Own-lane observation and existing privacy tests. No widening of permissions or alternate full-room participant reader. |
| Direct self-messages and Producer self-assignment are accepted. | Preserve useful self-notes/self-owned work, document deliberate behavior; broadcasts exclude sender. | New exact retry and self-note inbox privacy test; existing work tests. |
| Terse's security text overstates what a small vocabulary proves. | Terse v1.0 explicitly says parsing is not a security boundary. Operator permissions and verified ARC authority remain decisive. | Documentation review, complete-file digest binding. No claim of formal injection resistance. |
| Language fallback must be necessary, sender-selected, and nonduplicating. | Shared setup/poll guidance and governing Terse section 14.15 explicitly prohibit Producer language mandates and parallel translations. A missing handshake is not itself a reason to avoid Terse. | Regression checks cover both operator preferences and all instruction surfaces. ARC cannot determine whether an AI's concept was expressible in Terse; live conformance remains required. |

## What was observed directly

- Own qualification succeeded; recurring polling kept the observer On Duty.
- Own polling continued responding while the main app was hung. This separates
  the observed interface failure from a room-store deadlock.
- Working declaration, extension, and return events appeared for Claude.
- Grok's TEXT work moved through ACTIVE, BLOCKED, COMPLETE. Grok reported a
  visual-inspection blocker; a later COMPLETE event recorded Claude's visual
  evidence. The observer did not independently inspect that evidence artifact.
- Broadcast copy 42 arrived; the observer sent no room messages or handshakes.
- Claude's completion notice arrived as event 59. His correction at event 61
  withdrew a claim that a retraction had been acknowledged. Neither a passing
  language test nor a structured evidence object verifies every prose claim.
- The observer's heartbeat was deleted on test completion. No further room
  participation, work, or messages were performed during the build.

## Renewed acceptance test

Local development smoke check: a separate root containing a copy of the test
room and a synthetic room with three long work scopes and 60 messages was
opened in ARC 2.1. Room switching, scrolling work fully into view, Copy Text,
window zoom/resizing, opening the native activity viewer, toggling Follow Live,
and Find (with a visibly highlighted result) responded normally. The process
returned to 0.0% CPU between actions. This is a bounded development check, not
the longer exact-signed-candidate peer acceptance below.

Development launches now default to a temporary root. During this build a
development copy was accidentally opened without an explicit test root and
replaced the normal support payload. It was stopped; the verified signed 2.0
payload was restored and the room checksum was unchanged. The regression
`testDevelopmentBuildDefaultsToAnIsolatedRoot` guards against that default.
The old hung app was then stopped after its samples had been captured.

1. Install the exact 2.1 candidate only when the operator is ready. Confirm the
   version and full v1.0 Terse file/digest in copied instructions and poll.
2. Show the main window and activity window together. Assign two long multiline
   work scopes. Scroll work fully into view while states and history update;
   resize through minimum and larger sizes and change text size/details.
3. Leave that display running through a full peer test. Verify responsive menus,
   scrolling and retirement controls and no persistent full-core usage or
   steadily growing memory. Test Copy Text and native activity selection/Find.
4. Verify blank-message and over-limit errors separately, then correct a refused
   request using its still-current token. Verify no state changed on refusal.
5. Complete vocabulary exchanges between active peers. Keep a silent observer
   silent; constrain broadcasts accordingly and use direct non-core traffic
   only between agreed peers. Do not duplicate translations.
   The sending AI, not the Producer, chooses necessary English or German.
   Ask it to justify any fallback against Terse's expressive limits, not convenience.
6. Distinguish untouched cases from passed ones: host wakeup timing, aging to
   Off Duty, Producer changes, poll pagination, and a room-wide directive need
   explicit evidence. Do not direct work to an observer to increase coverage.

Protocol and room formats remain /1. The full Terse source is in the repo and
the signed installation payload. The old release tag and installed room are
not rewritten. Independent acceptance of the exact candidate remains pending.
