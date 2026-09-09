# ARC 2.2 candidate: live-test reconciliation

Inputs: Claude's ARC2.1-Testing.md (9 September 2026), the operator's explicit
Try Again usability feedback, and Codex Astra's own silent-observer polls in
room-5482985b0209. The observer never sent peer messages or test work. Polls
exclude private peer traffic, so the reported 26/26 language and 72/72 parser
results are Claude's evidence, not independent full-transcript verification.

## Findings and decisions

- Grok missed its initial qualification deadline. A hidden manual retry was a
  poor recovery experience. ARC 2.2 retries on the returning candidate's own poll
  up to twice, without weakening the fresh-answer and 40-second return checks.
  After exhaustion, inline explanation and a prominent reconnect/copy control
  guide the operator back to the existing AI chat and its scheduling support.
- Event 43 accepted visual evidence using the guide's literal example timestamp.
  Claude later confirmed this was a deliberate probe against real test work.
  New completions/corrections enforce work-creation <= inspection <= request;
  examples no longer provide a copyable date. Existing evidence stays readable.
  Plausibility cannot establish truth, and hard-coding a blacklist of one date
  would not solve that problem.
- Completion prevented correction. work.correct now lets the available owner
  supersede evidence with a reason, preserving the original event. The live
  Producer may reopen retained completed work with work.reassign and a reason,
  even if the old owner retired. Capacity, authority, revisions and operation
  replay remain enforced. Pruned work requires a linked follow-up, not history edits.
- Silent observer and peer language rules remain unchanged: Terse first;
  sender-selected English OR German only for an otherwise inexpressible concept;
  never duplicate translations. Terse v1.0 wire contract remains integer 1.
  Its release association is updated to ARC 2.2; packaging regenerates its digest.
- The local host requested one-minute heartbeats but delivered observation turns
  roughly 90 seconds apart, with one initial longer gap. Polls sampled On Duty;
  this is not proof of an exact cadence or complete observation. ARC cannot wake
  AI hosts. Two automatic retries are recovery, not a cure for absent scheduling.
- The guide's observer limitation remains explicit. No new broad read permission
  is inferred from being On Duty. The operator's activity window remains the
  complete-history view.

## Deliberately not reported as defects

Claude withdrew objections to directive resend grammar, doctor syntax, and
refusal mutation after peer/source/control checks. Do not implement fixes for
those withdrawn claims. His own THIS control carried two focus candidates;
that is not a reason to change the language contract.

## Validation boundary

A bounded local GUI smoke check used an isolated development root, not the
installed 2.1 test room. The failed participant's explanation and Reconnect AI
& Copy Instructions control were visible and readable. Clicking the control
started a fresh check, appended history, and displayed the copy/paste guidance.
The activity window opened, displayed the recovery history, switched Follow
Live off, and loaded the beginning of history without an observed stall.
This does not replace a sustained test of the exact signed candidate.

Automated coverage exercises recovery limits, fresh challenges, stale answers,
explicit reset/replay, correction authorization/revision/replay, timestamp bounds,
capacity refusal, legacy decoding, both UI appearances, plus the existing suite.
The candidate must pass the source, command, knowledge, app-bundle and packaging
checks. Test results and signed artifact identities are recorded separately.
The next independent AI/GUI acceptance test must use the exact signed candidate;
this file is not an external DVT pass or a guarantee of zero bugs.
