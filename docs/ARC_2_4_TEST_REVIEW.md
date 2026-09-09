# ARC 2.4: crash response and next-test plan

## Evidence and limits

The installed ARC 2.3.0 (230) crashed on September 9, 2026 at 05:53:05 PDT
on macOS 26.6.2. AppKit recorded 300 repeated layout iterations, followed by
NSGenericException for repeated window constraint updates. The main-thread
stack includes SwiftUI LazyLayoutViewCache phase invalidation. This is a
confirmed release-blocking UI crash, not evidence of a Terse parser failure.

The operator opened the observation window moments before the crash. Claude
reported no messages, structured packets, work or broadcasts before stopping;
his local Terse tools behaved normally. His last clean state included automatic
recovery for Grok. The retained event times put that recovery after the captured
crash, so it is not proof of the original trigger. Both observations inform
testing, not an unsupported causal conclusion.

The initial synthetic main-window and two-window recovery stress cases passed
on the old layout too. Opening the isolated old app's observation window did
not reproduce the exact exception. Do not call these a reproduced-crash fix
or claim zero bugs. No real-room polling was restarted for the investigation.

## Changes and verification routes

- RoomView no longer uses lazy stacks or starts history reads on row appearance.
  Eager main-history pages are bounded at fifty rows. Sequence boundaries keep
  older pages stable on new activity; failed reads cannot advance the page.
- ActivityTranscript uses proposed viewport dimensions instead of deriving
  the host's preferred size from document height. Resize callbacks guard reentry.
- Participant status/last-check-in changes no longer rebuild historical text;
  actor-name, event, font and room changes still do. A regression counts builds.
- `testRecoveryTransitionsWithHistoryRemainLayoutStable` exercises three AI
  cards, failed/retrying/qualified transitions, both windows, focus, multiple
  sizes, scrolling and advanced details. Existing tests retain duty, work,
  private messaging, Terse, replay, capacity, installation and integrity checks.
- `testHistoryPagesAreBoundedStableAndDoNotSkipOnFailedLoad` and
  `testDutyUpdatesDoNotRebuildTranscriptButNameChangesDo` cover the new bounds
  and redundant-work defect separately from the unreproduced crash trigger.

## Required next live acceptance test

Only after operator approval, install the frozen candidate using the ordinary
fresh-install process. Use new lane bindings. Let three AIs qualify, with one
Producer and a silent observer. Open/close the observation window repeatedly
while a delayed lane fails and automatically recovers. Resize both windows,
switch focus, scroll, enlarge text, expand details and change rooms. Confirm
both windows remain responsive and collect any AppKit layout warnings.

Test paging past fifty events, earlier/newer/newest navigation, a failed read,
Find, paused/follow-live scrolling, participant renaming and all Terse 2.0
features from ARC_2_3_TEST_REVIEW.md. Do not ask the silent observer to send a
declaration or a reply. Preserve one necessary fallback language per concept.

Full local checks and signed/notarized artifact verification are candidate
gates, not a substitute for this test or independent public-release DVT.

## Local pre-freeze results

`make check` passed twice with 137 tests and no failures. The recovery stress
includes a maximum-capacity 64-participant state, not only three cards.
The optimized arm64 app check also passed. A development-only app using copied
or synthetic room files passed observation-window open/close, Follow Live off,
native Find, and one-click earlier-page loading followed by Newest History.
The two-window stress and manual runs produced no repeated-constraint warnings
in the bounded unified-log check. These results are not an installed release
test; the operator's installed app and real participant polling remain stopped.
The regenerated two-page literature was rendered and visually reviewed.
