# Changelog

ARC uses semantic versions. Dates use ISO 8601.

## 2.5.0 — 2026-09-09 (unpublished candidate)

- Introduce Terse 2.1 / wire 3 as required for a normative contract change.
  Error replies name the failed token or section, never an ambiguous numeric
  utterance-reference label. Validate marked and conditional replies too.
- Preserve original wire-2 packet validation and rendering for ARC 2.3/2.4
  rooms. New events carry wire_version:3; old declarations cannot establish
  current agreement. Read results identify the original wire version.
- Clarify silent-observer instructions and actual transport limits. An
  unsolicited declaration is not agreement; observers do not answer requests.
  Document self-addressed packet requirements and all nine packet kinds.
- Add repair, historical-upgrade, compatibility, silent-peer and self-packet
  regressions. Retain the two-window layout, recovery, paging and evidence tests.
- Synchronize current specifications, command/help text, installation identity,
  literature and release documentation. Independent exact-candidate acceptance
  and measured cost benefits are not implied by local test success.

## 2.4.0 — 2026-09-09 (unpublished candidate)

- Remove lazy room/history view-phase churn implicated by the 2.3 AppKit
  constraint-loop stack. Main history uses bounded, sequence-anchored pages;
  the separate read-only window retains continuous history and Find.
- Stop history reads triggered by row appearance. A failed page read keeps
  the current page and all recorded events; no history is discarded.
- Keep transcript viewport sizing independent of text height; guard resize
  reentry and avoid rebuilding the transcript for status-only participant updates.
- Add real two-window recovery/resize/scroll/focus stress, bounded-page checks,
  and a regression for unnecessary transcript rebuilds.
- Refresh current specifications, literature, release identities and Terse's
  containing-product heading. Terse remains 2.0 / wire 2, with unchanged semantics.
- Exact original crash trigger is not yet reproduced. These changes remove
  observed risk paths; signed-candidate live acceptance remains required.

## 2.3.0 — 2026-09-09 (unpublished candidate)

- Add Terse 2.0 (wire 2), retaining thirty classic words and adding fixed,
  explicitly negotiated context, batch, results and dependency profiles.
- Add typed terse.send with atomic, private, replay-safe events; context
  references and bounded changed-field revisions; missing-baseline recovery;
  declarations scoped to specification digest and both participant bindings.
- Add local syntax checking, packet building, bound read/status tools, matched
  cost calculations and a native Terse Cost Comparison import screen. Reported
  actual figures and estimates remain separate; no provider integration or
  measured savings is claimed.
- Resolve the ARC 2.2 test's layout/prose-reference documentation gap and reject
  invalid utterance references in the typed Terse path. Keep sender-selected
  single-language fallback and silent-observer boundaries.
- Retain automatic recovery, evidence correction and completed-work reopening;
  extend tests and document a disposable-lane recovery test for the next round.
- Update current specifications, onboarding, CLI help, literature and artifact
  identities for ARC 2.3 / Terse 2.0. Older release tags remain unchanged.

## 2.2.0 — 2026-09-09 (unpublished candidate)

- Recover expired access checks on the returning AI's own bound poll, up to two
  automatic retries. Each still requires a fresh challenge and 40-second return.
  Show inline guidance, retry progress, and a prominent reconnect-and-copy action.
- Add owner-only work.correct for retained completed evidence, with a reason,
  current-revision check, immutable earlier history and idempotent retries.
- Allow the live Producer to reopen retained completed work through reassignment,
  including retired-owner recovery, while enforcing the 50-current-work limit.
- Reject new visual completion/correction timestamps before work creation or
  after the request. Replace copyable example dates with intentionally invalid
  placeholders. Preserve readability of legacy evidence; do not claim truth validation.
- Include recent completed evidence in its owner's poll for correction. Preserve
  private-message visibility, operation-token safety, and the Terse v1.0 language
  contract. Synchronize specifications, help, manuals, literature and packaging.
- Add recovery, correction, timestamp, capacity, legacy-record and rendered UI
  regression coverage. Exact-candidate independent live acceptance remains required.

## 2.1.0 — 2026-09-08 (unpublished candidate)

- Remove SwiftUI selectable-text overlays from the live main window after
  a captured main-thread layout spin and rapidly growing memory footprint.
  Main-window text offers Copy Text through its context menu and accessibility
  action; the separate native activity transcript retains selection and Find.
- Distinguish blank text from oversized text in validation errors. Add tests
  for Unicode byte limits, unchanged state, and corrected same-token retries.
- Document deliberate direct self-messages and Producer self-assignment;
  test self-message privacy and idempotence.
- Ship the full Terse contract v1.0 with per-recipient broadcast agreement,
  silent-observer precedence, and accurate limits on security claims.
- Designate Terse v1.0 as its first formal release, with integer handshake 1;
  earlier drafts predate versioning. Make the full language text governing ARC
  specification 013 and expose it through the verified specification reader.
- Require necessary prose fallback to be chosen by the sending AI, never the
  Producer. Prohibit parallel translations and convenience-based avoidance of
  Terse in onboarding, polling guidance, and the governing language contract.
- Add rendered main-window update/resize coverage and a guard against
  reintroducing the implicated text-selection path. The captured hang is real;
  the exact original trigger was not reproduced by the initial synthetic test.
- Isolate development app launches in a temporary data root unless a test root
  is explicitly provided. Signed release builds keep their standard location.
- Include the following source-specification corrections prepared after 2.0.
  Prior release artifacts and installed data are not rewritten by this build.

- Synchronize all ARC specification titles and current-behavior rules
  with current behavior, while retaining the actual protocol and storage format identifiers.
- Reconcile Working availability, the optional read-only activity window,
  full-room deletion recovery, action refusal/retry semantics, room creation
  replay, binding visibility, and the atomic installation receipt.
- Index the complete tracked Terse specification and its provenance;
  expand verification guidance for current behavior and language limitations.

## 2.0.0 — 2026-09-08 (unpublished candidate)

- Name the exact invalid evidence field and expected format. VISUAL timestamps
  still require valid UTC with six fractional digits; the guide now shows it.
- Add `message.broadcast`: identical addressed notices stored atomically for
  all other qualified peers with one operation, exact replay, and no partial
  delivery when capacity is exhausted. Private messages remain private.
- Clarify one-language-per-thought fallback: no unnecessary English/German
  translations or prose duplication of Terse. Operator replies use only the
  selected language; activity continues to show original peer messages.
- Ship revised Terse contract version 7: explicit, non-guessed THIS focus;
  mandatory repair when unclear; corrected FILE example; semantic version
  mismatch handling; no false promise of a unique encoding for equivalent claims.
- Clarify refused versus uncertain action outcomes, computed utterance references,
  silent-observer check-ins and inbox limits, and room-wide notice guarantees.
- Add regressions for real German Unicode, 63-recipient fan-out, exact retry,
  target eligibility, capacity refusal, and actionable evidence errors.
- Accept 2.x release identities throughout packaging and installation while
  retaining 1.x upgrade support; test fresh installation and cross-major upgrade
  against isolated fixtures without modifying the live ARC installation.
- Preserve protocol/1 envelopes and the existing room format. Older clients
  cannot issue the new broadcast request; existing room history remains readable
  by 1.1.0. Existing AIs must reread the changed Terse bytes on their next poll.
- This candidate is not installed or published; independent acceptance testing
  of the exact new build remains required before sealing a public release.

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
