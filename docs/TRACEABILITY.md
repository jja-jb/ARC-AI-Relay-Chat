# ARC 2.4.0 traceability

Terse 2.0 specification 013 sections 20–26 map to ARCTerseTests and the
Terse/ledger/score helpers in ARCCore. TERSE_MESSAGE uses the existing durable
codec and operation-token tests. ARCActivityWindowTests cover literal packet
rendering. The sidebar cost import is checked visually; it performs bounded
local file reading and computation off the UI thread. See TERSE_2_GUIDE.md and
ARC_2_3_TEST_REVIEW.md for the exact feature and next-test mapping.

Every determining requirement has one explicit implementation owner and one
verification route below. `make check` proves local evidence. DVT proves the
human, host, installation, and exact signed-candidate behavior that automation
cannot honestly prove. An unlisted identifier, implementation surface, or
public behavior fails `source-check`.

## Local regression additions — September 2026

ARC 2.4: UI-001/UI-003 map to
`testRecoveryTransitionsWithHistoryRemainLayoutStable`,
`testHistoryPagesAreBoundedStableAndDoNotSkipOnFailedLoad`, and
`testDutyUpdatesDoNotRebuildTranscriptButNameChangesDo`. These exercise the
two-window recovery stress path, bounded non-lazy history and status-only
transcript updates. ARC_2_4_TEST_REVIEW.md records the crash evidence and limits:
the original exception has not been reproduced by the synthetic tests.

Retained from ARC 2.3: QD-005/QD-008 and UI-003 are covered by
testAutomaticRecoveryIsBoundedFreshAndRestartsOnlyOnOwnPoll and
testConnectionRecoveryGuidanceIsExplicitAndRendersBothAppearances. MW-005/MW-007,
CLI-008 and REC-010 are covered by
testCompletedEvidenceCorrectionIsAuthorizedRevisionedAndReplaySafe,
testVisualCompletionAndCorrectionRejectOutOfLifetimeTimes,
testReopeningCompleteWorkRespectsCurrentCapacityAndPreservesToken and
testRecoveryAndCorrectionValidateDurableShapeAndOldRecords. The live 2.1 report
and observation reconciliation is in ARC_2_2_TEST_REVIEW.md. These tests establish
bounded recovery and audit behavior, not AI comprehension or honest evidence.

ARC 2.1: `testMainWindowDoesNotReintroduceSwiftUISelectionOverlay` and
`testLiveRoomWorkLayoutRemainsResponsive` cover UI-001's copy-safe main window,
rendered work updates, scrolling and resizing. Activity transcript tests retain
native selection/Find coverage. The original hang was captured twice in the
installed 2.0 app; the initial synthetic rendering test alone did not reproduce
its exact trigger. Removing that overlay is directly tied to the captured
stacks, not a claim that every possible interface stall has been excluded.
`testBlankMessageErrorsAndByteBoundsPreserveStateAndToken` and
`testDirectSelfMessageIsDeliberateAndRetryDoesNotDuplicate` cover MW-003's
diagnostics, Unicode boundary, refusal/retry, and self-note privacy. Terse's
full v2.0 bytes and per-recipient broadcast rule are pinned in packaging
tests. Live AI conformance and independent acceptance remain separate gates.
Development-root isolation is covered by
`testDevelopmentBuildDefaultsToAnIsolatedRoot`; release builds retain the
standard root and ignore development overrides. The bounded manual interface
smoke check is recorded in ARC_2_1_TEST_REVIEW.md.

The source specification set is synchronized to ARC 2.4.0 behavior. Room,
protocol, qualification, knowledge Profile 1, and report schema identifiers
retain their own versions; they do not become /2 because the product is 2.4.
The complete Terse v2.0 source remains in languages/terse/ as governing ARC
specification 013, mapped through QD-001 / IR-003 and CLI-002. Its separate
signed file preserves the Profile 1 format. The full verified text is exposed
by `arc spec read 013`; `testGoverningTerseSpecificationReturnsOnlyCompleteVerifiedBytes`
checks exact content and fail-closed verification. Sender-selected necessary
fallback and the prohibition on duplicate translations are checked by
`testFallbackIsSenderChosenTerseFirstAndNeverDuplicatedOnEverySurface`.
Expanded manual cases in DVT_GUIDE.md describe required checks, not completed
external acceptance evidence. Existing frozen artifacts are not rewritten.

ARC 2.0: `testVisualTimestampRefusalNamesFieldPreservesStateAndTokenThenCorrectedRetryWorks`
and `testEvidenceErrorsIdentifyShapeFieldsAndConsistencyWithoutEchoingContent`
cover MW-007 / CLI-008 field-level diagnostics, strict UTC form, safe refusal and
retry. `testRoomWideNoticeUsesOneAtomicOperationAndExactUnicodeTextFor63Peers`
and `testBroadcastExcludesUnqualifiedRetiredSelfAndRejectsUnavailableSender`
cover MW-003 / CLI-008 room-wide fan-out, Unicode preservation, private inbox
filtering, eligibility, and replay. The full-room retirement test now also
proves broadcast refusal leaves bytes unchanged. Communication tests enforce
the shared nonduplicating language policy in onboarding and every poll.
At 2.0, dev-tool tests pinned development draft 7; the current tests pin the
formal Terse v2.0 bytes. Retained checks cover explicit focus/repair,
version contract, corrected FILE example, and packaged digest. These textual
checks are not a claim of semantic understanding by any AI.
Installation regression `testVersionTwoFreshInstallUpgradeAndInvalidVersions`
covers isolated fresh 2.0 payload publication, upgrade from 1.1.0, and unchanged
installed bytes after rejection of malformed or unsupported release identities.

Core tests cover creation replay after rename, Working admission, deadline
extension/replay/expiry/return, clock rollback, hostile instruction FIFOs, and
normal-write capacity reserved for complete retirement and deletion. App tests
cover missing installed payload repair, creation retry tokens, preserving
loaded history across multi-page refresh, restarting observation after failed
confirmed mutations, and Working labels/deadlines. Dev-tool tests exercise
hostile unsigned container geometry and every mounted release-check failure
with inert command stubs. Release signing, notarization, and external DVT are
not replaced by these tests. Legacy full-room tests verify that exceptional
deletion requires insufficient retirement capacity and refuses newly On Duty
or Working AIs, active qualification, and unavailable time. Ordinary inactive
rooms still require retirement. The app test verifies the explicit warning
and cancellation. No history is trimmed to make room.

Terse integration: `Communication.swift`, the handoff/guide, poll response,
sidebar language selector, and manifest build/install checks cover QD-001,
MW-003, UI-002, CLI-007, and IR-003. `ARCCommunicationTests` verifies digest
changes in existing rooms, language persistence, unavailable notices, hostile
paths and size limits, and canonical line-ending transport. App tests cover
copy text, saved selector state, failed saves, installation/upgrade/repair, and
preserving operator preferences. Dev-tool tests bind the supplied full text to
its digest and reject mismatched packaged files. No test claims AI compliance
or measured accuracy/cost gains.

## Constitution and reading rules

Implementation: specifications 000–001, public documentation, and
`ReleaseSupport.checkSource`. Verification: `source-check`, `make check`,
DVT-001, DVT-004, DVT-012, and DVT-014.

- `C-001` PURPOSE
- `C-002` SIMPLICITY IS POWER
- `C-003` HUMAN ROLE
- `C-004` VISIBLE TRUTH
- `C-005` LOCAL, PRIVATE, AND AI-AGNOSTIC
- `C-006` SEALED AND HUMAN-READABLE KNOWLEDGE
- `C-007` COMPLETE PRODUCT, NO ARTIFICIAL GATES
- `C-008` ONE PRODUCT FOR TWO AUDIENCES
- `C-009` MODEST PUBLIC VOICE
- `C-010` DETERMINING RULE
- `READ-001` DETERMINING SET
- `READ-002` REQUIREMENT WORDS
- `READ-003` PRECEDENCE
- `READ-004` ONE FACT, ONE OWNER
- `READ-005` HUMAN AND ENGINEERING WORDS
- `READ-006` COMPLETION

## Room, Administrator, AI, and Producer

Implementation: `Types.swift`, `RoomDocument.swift`, `Store.swift`,
`AppState.swift`, and `RoomView.swift`. Verification: ARCCore and ARCApp room,
participant, binding, qualification, Producer, status, limit, and lane tests;
DVT-004 through DVT-008.

- `RM-001` ONE ROOM IDENTITY
- `RM-002` ONE HUMAN ROLE
- `RM-003` PARTICIPANT IDENTITY AND LANE BINDING
- `RM-004` ONE PARTICIPANT LIFECYCLE
- `RM-005` ONE PRODUCER
- `RM-006` NO QUALIFICATION LIMBO
- `RM-007` ONE PLAIN ROOM STATUS
- `RM-008` CONTROLS ARE ALWAYS FINDABLE
- `RM-009` ROOM AND LANE ISOLATION

## Durable state and records

Implementation: `RoomDocument.swift`, `RoomFile.swift`, `Store.swift`, and
`Types.swift`. Verification: canonical-byte, malformed-relationship, bounds,
complete-history, lock, atomicity, deletion, retry, clock, and recovery tests;
DVT-010 and DVT-011.

- `DS-001` ONE ROOM, ONE RECORD
- `DS-002` CANONICAL ROOM BYTES
- `DS-003` ONE LOCKED REVISION
- `DS-004` ATOMIC PUBLICATION
- `DS-005` REVISION AND SEQUENCE
- `DS-006` PORTABLE NONDECREASING TIME
- `DS-007` ACTIVITY LASTS AS LONG AS THE ROOM
- `DS-008` COLLECTION AND MEMORY BOUNDS
- `DS-009` OPERATION RETRY
- `DS-010` REFUSAL AND RECOVERY
- `DS-011` PERMANENT ROOM DELETION
- `REC-001` AUTHORITATIVE BYTES
- `REC-002` TOP-LEVEL RECORD
- `REC-003` ROOM
- `REC-004` PARTICIPANT
- `REC-005` QUALIFICATION
- `REC-006` AI OPERATION REPLAY
- `REC-007` WORK
- `REC-008` EVIDENCE
- `REC-009` EVENT
- `REC-010` EVENT VOCABULARY
- `REC-011` IDENTIFIERS, TEXT, TIME, AND DIGESTS
- `REC-012` BOUNDED JSON
- `REC-013` MUTATION AND TIME
- `REC-014` FILE TRANSACTION
- `REC-015` VERSION AND RECOVERY RULE

## Messages and work

Implementation: `ActionJSON.swift`, `Store.swift`, `RoomDocument.swift`, and
`RoomView.swift`. Verification: strict-action, replay, directed-message, work,
reassignment, unavailable-owner, evidence, and Activity-presenter tests;
DVT-009.

- `MW-001` ONE TRUSTED ENVELOPE
- `MW-002` ONE EVENT STREAM
- `MW-003` MESSAGES ARE INERT NOTICES
- `MW-004` ONE WORK MODEL
- `MW-005` SIMPLE REASSIGNMENT
- `MW-006` ONE POLL
- `MW-007` TEXT AND VISUAL EVIDENCE
- `MW-008` ONE UNDERSTANDABLE MAC VIEW

## AI instructions, qualification, and duty

Implementation: `AppState.swift`, `Store.swift`, `ARCCommand/main.swift`, and
`docs/ARC_AI.md`. Verification: copied-handoff, guide, qualification schedule,
expiry, retry, poll, binding-redaction, clock, and monitor-recovery tests;
DVT-005, DVT-006, and DVT-010.

- `QD-001` ONE GENERIC AI GUIDE
- `QD-002` ONE AI INSTRUCTIONS CONTROL
- `QD-003` AI-AGNOSTIC BASELINE
- `QD-004` ONE FIXED QUALIFICATION TEST
- `QD-005` THREE OPPORTUNITIES IN TWO MINUTES
- `QD-006` ONE PORTABLE DUTY POLL
- `QD-007` NO FALSE WAKE CLAIMS
- `QD-008` CLEAR RECOVERY AND RETIREMENT

## Mac application

Implementation: `ARCApp.swift`, `MainView.swift`, `RoomView.swift`, `ActivityWindow.swift`,
`AppState.swift`, and `ARCInstallation.swift`. Verification: ARCApp client,
help, large-text, monitoring, paging, interruption, install, deletion, and
recovery tests; `ARCActivityWindowTests` covers read-only native text, literal
message rendering, event labels/colors, room changes, Follow Live on/off,
initial layout, and anchored earlier-history paging. DVT-003, DVT-004,
DVT-013, and DVT-014 remain the manual application checks.

- `UI-001` ONE ORDINARY PRODUCT
- `UI-002` FIRST USE IN MINUTES
- `UI-003` ONE ROOM READING ORDER
- `UI-004` ADMINISTRATOR CONTROL NEVER DISAPPEARS
- `UI-005` MENUS AND KEYBOARD
- `UI-006` PLAIN CONFIRMATIONS AND ERRORS
- `UI-007` HELP AND PRIVACY IN THE APP
- `UI-008` ACCESSIBILITY AND AGE-14 CLARITY
- `UI-009` RESPONSIVE LOCAL OPERATION
- `UI-010` DIRECT CORE AND ONE RECORD
- `UI-011` INSTALLATION FAILURE IS RECOVERABLE
- `UI-012` RETAINED AND FRESH ROOMS ARE DISTINCT
- `UI-013` NO DOCUMENT PRODUCT SURFACE

## Native command

Implementation: `ARCCommand/main.swift`, `ActionJSON.swift`, `Store.swift`,
and `Knowledge.swift`. Verification: `command-test`, strict-action,
binding-redaction, replay, paging, and Diagnose tests; DVT-005 and DVT-009
through DVT-012.

- `CLI-001` PURPOSE AND SINGLE IMPLEMENTATION
- `CLI-002` COMPLETE GRAMMAR
- `CLI-003` INPUT LIMITS AND DIRECT ARGUMENTS
- `CLI-004` GUIDE
- `CLI-005` MACHINE FRAMING
- `CLI-006` COMMON VIEWS
- `CLI-007` POLL
- `CLI-008` ACTION OBJECTS
- `CLI-009` OPERATION REPLAY
- `CLI-010` DOCTOR
- `CLI-011` ERRORS, RETRY, AND EXIT STATUS
- `CLI-012` SECURITY AND PORTABILITY

## Security and privacy

Implementation: `RoomFile.swift`, `RoomDocument.swift`, `Store.swift`,
`Knowledge.swift`, `ARCInstallation.swift`, and `PrivacyInfo.xcprivacy`.
Verification: link/path, bounds, canonical refusal, content-redaction,
diagnosis, deletion, installer, privacy, and source checks; DVT-011, DVT-012,
and DVT-015.

- `SP-001` HONEST TRUST BOUNDARY
- `SP-002` LOCAL AND OFFLINE
- `SP-003` TEXT NEVER BECOMES AUTHORITY
- `SP-004` PATH AND FILE SAFETY
- `SP-005` BOUNDED INPUT
- `SP-006` ONE ROOM CANNOT REDIRECT ANOTHER
- `SP-007` SAFE PUBLICATION AND RECOVERY
- `SP-008` PERMANENT DELETION IS EXPLICIT AND NARROW
- `SP-009` DIAGNOSTICS MINIMIZE CONTENT
- `SP-010` INSTALLATION AND RELEASE SAFETY

## Installation and release

Implementation: `Package.swift`, `Makefile`, `ReleaseSupport.swift`,
`ReleaseEvidence.swift`, installer code, release documents, and CI.
Verification: source, knowledge, arm64 app, manifest, candidate, strict DVT,
seal, checksums, license, and publication checks; DVT-001 through DVT-003 and
DVT-015.

- `IR-001` ONE NATIVE PRODUCT
- `IR-002` ORDINARY MAC DELIVERY
- `IR-003` ONE ATOMIC INSTALLED PAYLOAD
- `IR-004` CANONICAL INSTALL MANIFEST
- `IR-005` SAFE REPLACEMENT
- `IR-006` COMPLETE SOURCE TREE
- `IR-007` BUILD INPUTS AND REPRODUCIBLE CHECKS
- `IR-008` HUMMINGBIRD LICENSE
- `IR-009` PUBLIC RELEASE ASSETS
- `IR-010` TWO-PHASE RELEASE EVIDENCE
- `IR-011` PUBLICATION AND REPOSITORY QUALITY

## Verification and publication

Implementation: this index, `Makefile`, Swift/C tests, `ReleaseSupport.swift`,
`ReleaseEvidence.swift`, and DVT documents. Verification: `make check`,
`app-release-check`, strict external DVT validation, and `release-seal`.

- `TV-001` COMPLETE MEANS PRESENT AND TESTED
- `TV-002` SOURCE-SCOPE AUDIT
- `TV-003` AUTOMATED NATIVE VERIFICATION
- `TV-004` DURABLE-RECORD PROOF
- `TV-005` AI PROTOCOL PROOF
- `TV-006` MESSAGE AND WORK PROOF
- `TV-007` HUMAN-EXPERIENCE DVT
- `TV-008` INSTALLATION AND OFFLINE DVT
- `TV-009` RELEASE-CANDIDATE DVT
- `TV-010` SEAL AND PUBLICATION CHECK

## AI knowledge container

Implementation: `arc_knowledge.h`, `arc_knowledge.c`,
`KnowledgeContainer.swift`, and the determining plain-text members.
Verification: C boundary/adversarial tests, deterministic build, validation,
deconstruction/reconstruction byte comparison, and source/app identity checks;
DVT-001, DVT-002, and DVT-012.

- `AKC-001` PURPOSE AND BOUNDARY
- `AKC-002` LIMITS AND INTEGER RULES
- `AKC-003` BYTE-EXACT HEADER
- `AKC-004` BYTE-EXACT DIRECTORY ENTRY
- `AKC-005` CANONICAL NAMES AND PROFILE
- `AKC-006` PAYLOAD PARTITION AND TEXT
- `AKC-007` VALIDATION AND OPTIONAL OMISSION
- `AKC-008` FIXED TYPED C INTERFACE
- `AKC-009` LIFETIME AND INTERPRETER RULE
- `AKC-010` DETERMINISTIC CONSTRUCTION
- `AKC-011` HUMAN-READABLE DECONSTRUCTION
- `AKC-012` STABLE REFUSALS
- `AKC-013` REQUIRED VERIFICATION

The final DVT report supplies tester identity, independence, time, Apple
silicon machine, system, toolchain, prepared hashes, deviations, and the result
for every DVT row. Release metadata and `SHA256SUMS` bind that evidence to the
exact published bytes.
