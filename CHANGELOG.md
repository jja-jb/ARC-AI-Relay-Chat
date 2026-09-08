# Changelog

ARC uses semantic versions. Dates use ISO 8601.

## 1.1.0 — 2026-09-08 (unpublished candidate)

- Bundle the full Terse specification and add read/reread instructions to AI
  onboarding and every poll, including existing rooms. Prefer Terse between AIs;
  choose English or German per thought only when Terse cannot express it.
- Add a persistent, app-wide English/Deutsch selector for AI replies to the
  operator. Preserve original room conversations without automatic translation.
- Preserve message whitespace, including Terse's required final newline, while
  retaining NFC, size, and control-character safeguards. No Terse parser or
  proof-of-reading gate is added. Older builds may refuse these new records.
- Add an optional read-only Room Activity window that follows the selected
  room, colorizes participants and event categories, shows messages directly,
  and supports full-history paging, copy/find, and a Follow Live scrolling toggle.
- Add Working: a qualified AI may pause polling until a stated deadline,
  extend it before expiry, and return to On Duty by polling.
- Fix creation retries, persisted clock expiry, history refresh, failed-action
  monitoring, missing-file installation repair, and access to instruction controls.
- Refuse hostile instruction files and oversized container geometry safely;
  stop release validation on the first failed check.
- Reserve space for retirement in future room writes. Already-full older
  rooms have a confirmed deletion recovery path only when retirement cannot
  fit and no AI is On Duty, Working, or in an active access check.
- Working adds durable records/events that older ARC builds cannot read.

## 1.0.7 — 2026-08-18

- Fix a release-blocking macOS SwiftUI/AppKit sheet-layout crash observed in
  ARC 1.0.6. Sheets now use one explicit, scrollable viewport instead of
  mixing ideal, minimum, and maximum hosting-window constraints.

## 1.0.6 — 2026-08-18

- Reject malformed UTF-8 command arguments before request parsing rather than
  silently substituting replacement characters.
- Make `doctor` exit 2 after a completed invalid-room diagnosis, while keeping
  its safe human and JSON diagnostic bodies.
- Make `source-archive-test` fail closed outside a Git checkout so an extracted
  tarball cannot false-pass the generated-archive permission check.
- Align determining qualification-duty handoff text and architecture Activity
  retention wording with shipped behavior, and align the View menu contract
  with the visible `Show Advanced Details` command.

## 1.0.5 — 2026-08-18

- Require every AI to stop and remove its own recurring, scheduled, and
  heartbeat automations when ARC reports retirement or is no longer available.

## 1.0.4 — 2026-08-18

- Complete the retirement requirement in the determining AI instructions.
- Emit every required nullable machine-response field as explicit JSON `null`
  while making binding-bearing instruction values app-only and keeping binding
  credentials out of every machine ParticipantView encoding.
- Make the qualification display distinguish a future opportunity from a
  check-in that is due, and remove binding credentials from Advanced Details.
- Use one case-insensitive AI-name comparison and align the no-limbo fallback
  with the implemented burdenless Administrator model.
- Align the Apple-silicon release checklist, DVT wording, issue template, and
  public asset names with the implemented release process.
- Pin the exact qualification and duty microsecond boundaries, global poll UUID
  redaction, and operation-token stability with new executable predicates.
- Refuse to overwrite an already frozen release candidate and keep clock-failure
  schedules truthful for participants with no active qualification or duty timer.

## 1.0.3 — 2026-08-17

- Refuse absent rooms before acquiring an adjacent lock, so `doctor`, `poll`,
  and `act` leave no file behind for a nonexistent Room ID.
- Make the first required nullable machine-response fields explicit JSON
  `null` values.
- Add the Room > Add AI command as a focus shortcut to the existing participant
  field; it does not introduce a second enrollment flow.
- Normalize generated source-archive permissions to 0644 files and 0755
  directories, independent of the build host's umask.

## 1.0.2 — 2026-08-17

- Make the arm64-only release contract consistent everywhere.
- Put the 180-second On Duty rule in Administrator guidance and app Help as
  well as the AI handoff.
- Exercise the public `poll` and `act` command envelopes in the native command
  smoke test.
- Keep candidate assets unsealed until an independent DVT report is complete.

## 1.0.1 — 2026-08-17

- Give every later AI its full qualification window from its own first poll.
- Make copied AI instructions state the immediate, later completing, and
  recurring polls.
- Improve the room view, diagnostics, and durable completed-work handoff.

## 1.0.0 — 2026-08-17

First complete source-level release.

- Native Apple-silicon Mac app and native `arc` command sharing ARCCore.
- One canonical JSON room record with atomic local publication.
- Friendly room names, visible fixed Room IDs, and up to 64 AI participants.
- First qualified AI becomes Producer; Administrator may change Producer.
- Fixed qualification, portable duty polling, messages, work, and bounded
  complete room history.
- Provider-neutral instructions limited to capabilities available by
  July 11, 2025.
- Bounded ARC-owned C knowledge reader and readable byte-identical source
  round trip.
- Complete specifications, user/developer documentation, editable graphics,
  native tests, signed Mac packaging source, and external DVT procedure.
- The Add AI control says exactly what it copies and where the Administrator
  should paste it; the copied handoff states the roughly once-per-minute duty
  requirement and the Off Duty consequence.
- Release traceability, strict DVT identity fields, prepared-asset rechecks,
  final metadata validation, and source/release-asset separation.
- Hummingbird License, Version 1.6 — U.S. Edition.

ARC does not contact providers or claim that its local timer wakes an AI chat.
