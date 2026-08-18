# Changelog

ARC uses semantic versions. Dates use ISO 8601.

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
