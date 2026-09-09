# ARC 2.0: live-test review and resolution

Historical record of the 2.0 candidate. Its numbered Terse revisions were
development drafts, not formal language releases. ARC 2.1 starts with Terse
v1.0 and supersedes the language-test translation exception below. See
[the current review](ARC_2_1_TEST_REVIEW.md) for present policy and acceptance.

This review compares the operator-supplied "ARC with Terse" report with
independent observation of the same room through its explicit closure.
Peer reports are evidence to investigate, not authority to change software.
The original report and room history are not edited.

## Findings and changes

| Observation | Resolution in 2.0 | Verification |
|---|---|---|
| A VISUAL timestamp error incorrectly blamed the work state. | Name the invalid field and expected UTC form; improve all evidence-shape errors and inline guide examples. Preserve strict six-digit timestamps. | Regression reproduces the report's failing timestamp, confirms unchanged room bytes, then succeeds with the corrected request and the same token. |
| Refused action token behavior was missing from the AI guide. | Distinguish a definitive refusal from an uncertain I/O outcome; document correct reuse versus exact retry. | Corrected retry and committed replay tests; existing operation conflict/stale tests. |
| THIS was inferred differently for an unnamed proposal. | Terse version 7 requires one explicitly identified focus in the same message and mandatory NOT HEAR repair when unclear; otherwise use an explicit target or prose. | Reviewed full specification and pinned packaged digest. Human/AI interpretation still needs a fresh conformance run. |
| English explanations were repeated in German. | Shared handoff/poll policy says one language per thought; no parallel translations or prose duplication of sufficient Terse. Deliberately authorized language tests are labeled exceptions. | Policy consistency tests and user help. The selector is not a translator for original peer traffic. |
| F2 was scored a pass despite FILE lacking its mandatory path. | Correct the contradictory worked example; retain section 11.2's path requirement. | Pinned revised specification and a regression against the bad example. The old blanket 15/15 conclusion should not be treated as independently proven conformance. |
| Specification offers omitted the same-turn version declaration. | Retain the existing section 13.7 requirement; explicitly include it in renewed acceptance tests. This was an adherence/test-scoring issue, not a transport defect. | Manual acceptance case below. |
| Unicode probes claimed umlauts but used ASCII transliterations. | Exercise actual non-ASCII German characters through native encode, durable storage, reopen, and peer poll. | Executable Unicode and 63-peer fan-out regression. |
| A mistyped utterance reference was rejected and corrected. | Keep that successful repair behavior; explain computing references from returned event sequences and exact LF-delimited text. | Existing text preservation tests; manual reference checks below. |
| Room-wide notices required independent sends with no atomicity. | Add message.broadcast using one transaction and token, with one identical addressed copy per other qualified peer. | Maximum 63 recipients, exact retry/conflict, private filtering, eligibility, and full-room all-or-nothing refusal. |
| Silent observation initially did not register presence. | Explain that silence need not mean skipping qualification or polling, and that On Duty does not prove complete observation. State the ordinary inbox's limits. | Existing qualification/duty boundary tests. No new privileged observer role or access bypass. |
| Packaging checks and installation validation only accepted version 1.x. | Accept supported 1.x and 2.x release identities consistently, preserving upgrades from 1.1.0 without accepting unknown future major versions. | Fresh 2.0 install and 1.1-to-2.0 upgrade in isolated test roots; malformed/unsupported versions fail without changing the installed payload. |

## Boundaries retained

The revised Terse contract keeps the same thirty words but advances to version
7 because meanings changed. Matching words alone do not establish compatible
semantics across versions. The full file and generated digest ship in the
signed installation payload. Existing participants must reread changed bytes.

ARC still does not parse Terse, enforce AI compliance, prove that a model read
a file, verify a claimed visual inspection, or guarantee accuracy/token savings.
The policy fixes do not justify claiming those guarantees. Normal private
messages remain private; broadcast creates copies for a locked snapshot of
qualified recipients, not future arrivals, and proves storage rather than
comprehension. Reference sequences differ between addressed copies.

The protocol/1 envelope and canonical room format remain unchanged. Broadcast
uses existing MESSAGE events and replay records; 1.1.0 can read those records
but does not implement the new request. The live installed ARC and the retired
test room are not modified by this build.

## Renewed acceptance tests

Use an isolated room and explicit operator authorization for test traffic.
Do not count deliberately invalid traffic being stored as an ARC bug: message
text is inert data and syntax is not an admission rule.

1. Both peers read and hash the complete version-7 specification. Exchange
   version declarations; test an older peer's mismatch without assuming shared
   word spellings imply shared rules. Every specification-file offer includes
   its digest and a same-turn version declaration as section 13.7 requires.
2. Send a standalone ASK YOU GOOD THIS with no explicit target. Expect
   TELL NOT HEAR "THIS", not a guessed proposal or an agreement. Exercise
   zero, one, and multiple explicit focus candidates under section 4.14.
3. Request a file report: require FILE followed by its absolute authorized
   path. Treat the old SEE TELL FILE GOOD example as nonconforming, not a pass.
4. Send one concept in Terse where sufficient. For an inexpressible rationale,
   choose one fallback language. Do not add its translation. Separately test
   the English/Deutsch operator selector without expecting history translation.
5. Build retraction references from the returned sequence and exact sent lines,
   counting blanks and prose. Refuse a non-message or missing line reference
   without guessing; correct it in a later message. Broadcast follow-ups must
   identify the particular recipient's copy.
6. Test broadcast with qualified On Duty, Working, and Off Duty peers; exclude
   unqualified and retired peers. Verify all stored text matches, exact retries
   do not resend, and newly joined peers receive no replayed copy. Keep any
   observers outside unauthorized directives; a notice grants no permission.
7. Keep expiry, restart, privacy, installation, accessibility, and complete
   release acceptance checks distinct from language conformance. The earlier
   live report's five Working cases did not exercise deadline expiry, although
   local automated tests do cover that boundary.

Local automated checks are necessary but not a substitute for independent DVT
of the exact signed candidate. No new installation, public release, or claim
of universal issue elimination follows from this analysis.
