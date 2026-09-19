# ARC 3.2.2 production release decision

Joseph Austin authorized Codex Astra Master Developer to lead the Pre-Push
ARC Test as Producer, assess Claude's independent critique, make final
technical decisions, and produce a new release for GitHub. Joseph remains
the sole human release authorizer; no additional human approval is required.

## Scope

ARC 3.2.2 / build 322 includes Quinby's Corner, indexed history, blocking
waits, delta polls, per-AI usage meters and the associated specifications,
privacy disclosures, user documentation and editable marketing materials.
It retains Terse 2.1 / wire 3 with unchanged specification bytes.
Earlier published releases and tags are not replaced.

## Evidence and disposition

Codex and Claude qualified in the installed 3.2.1 review room, completed
their Terse declarations, and exercised Producer work assignment, worker
progress/completion, private messages and continuing duty. Claude independently
checked source behavior, signing and notarization of that installed baseline.
This is attributed peer review, not an independent DVT certificate for 3.2.2.

The final source incorporates these corrections:

- Corrupt Corner data can be removed by explicitly confirmed reincarnation
  under the existing validated lock, including when no initial snapshot is
  readable. Ordinary reads remain fail-closed. Unsafe links are refused,
  old memberships are invalidated and ordinary rooms remain intact.
- Off-state waiting no longer repeatedly returns without waiting; Off/On
  transitions still wake a host. Cursor catch-up remains explicit.
- Concurrent room-meter writes no longer overwrite other lanes' counts.
- Missing intermediate history is visibly disclosed until paging fills it.
- Setup, Help, Privacy and repository policy explain waiting, costs,
  cross-room copies and retention consistently.
- The 80-transition UI crash regression checks geometry and state on every
  transition, with a bounded runaway guard. Its previous aggregate 30-second
  limit failed on a shared macOS 15 runner despite completing every transition;
  this test is not a calibrated rendering-performance benchmark.

Regression tests reproduced corruption-reset and meter-concurrency failures
before their fixes and passed afterward. The full 176-test suite passed with
zero failures; make check and the optimized arm64 app-release-check passed.
Updated Privacy and history-gap views, and both literature pages, were
rendered and visually inspected.

The installed live room remained on 3.2.1 during this review. Tests of the
new 3.2.2 paths used isolated roots and the compiled app/core, not a claim
that the live review installation had already been replaced.

## Accepted boundaries

Hosts must carry next_after, complete required catch-up and follow the
qualification schedule. Deliberately repeating an obsolete cursor is not
made a new ARC protocol or an artificial release gate. Same-state work
progress updates remain an optional future feature; ordinary messages can
carry interim progress now.

Meters are volatile, best-effort counters of ARC requests and bytes, not
provider billing records. A busy or unavailable meter must not fail a room
action; an empty lock file is retained to preserve cross-process locking.
ARC does not guarantee provider savings, host execution, model understanding,
or erasure from external AI chats, backups or physical media.

## Final package identity

The production assets include PRODUCTION-ACCEPTANCE.md and
PRODUCTION-METADATA.json with the exact tagged commit, actual signature and
notarization results, bundle/source verification, and payload checksums.
Those external records avoid a source-commit self-reference. This source
decision alone is not evidence that packaging or publication has completed.
