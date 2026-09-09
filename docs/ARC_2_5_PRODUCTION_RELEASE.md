# ARC 2.5.0 production release decision

Date: 2026-09-09. Decision: approved for general availability by the maintainer.
ARC 2.5.0 (250), Terse 2.1 / wire 3. Apple silicon; macOS 15 or later.

## Acceptance basis

The maintainer reported completing all human-facing tests while the three AIs
performed the room tests, then directed completion of production publication.
That is maintainer-reported acceptance, not independent instrumentation or a
claim that every detailed DVT row was witnessed by the builder.

Local builder checks passed 140 native tests and command, knowledge and app
checks. The signed/notarized candidate was exercised locally and its signatures,
staples and hashes verified. GitHub CI passed both jobs at ec12068aa475637de419d0a3ab5a8575392a5507,
including the full native check on macOS 15 with Swift 6.1.2.

The final participant-lane test reported no ARC software defect: 42 validator
cases, 31 packet-builder cases (one corrected tester expectation), 36 typed
request refusals on a surviving operation token, nine scorecard cases, all nine
packet kinds and live peer exchanges. These are tester-reported counts.
The observer directly saw responsive polls, public work and duty transitions,
evidence correction and completion notices; it did not inspect private peer
exchanges or independently verify the visual artifacts.

No confirmed application defect was identified as a production blocker.
This does not guarantee absence of bugs, perfect AI compliance or token savings.

## Known limitations and exact provenance

- The frozen source archive's test fixture exceeds Swift 6.1.2's type-checking
  limit. Apply the attached SOURCE-TEST-COMPATIBILITY.patch before running its
  tests, or use main, which includes that correction. It changes only a test
  fixture, not shipping code or test coverage. The frozen archive is not
  represented as passing unmodified on Swift 6.1.2.
- The signed app, bundled specifications, literature and source archive retain
  their original candidate-era text and some old repository links. The current
  download location is github.com/jja-jb/ARC-AI-Relay-Chat. Release status is
  recorded here and on GitHub; signed bytes are not rebuilt to change a label.
- A silent observer is an instruction, not an enforced ARC transport role.
  The final observer received both an unsolicited handshake and a declaration
  and replied to neither. Generic prohibitions were already in the setup;
  do not claim guidance reliably prevents such contact.
- AI fallback-language necessity and lack of redundant translations cannot be
  guaranteed by syntax validation. No matched actual-cost comparison was run.
- The observer briefly became Off Duty after test completion during release
  work, then returned. Do not claim uninterrupted observation after completion.

The unchanged tested DMG SHA-256 is
`c8533e81fc035a66db6024a4a7845301be39b170cf16b2940d39e4ce494241b7`.
The four original candidate assets correspond to annotated tag v2.5.0 at
`32ea066d25382944565de9c40098542bed63bbff`.
Main adds public-documentation updates and the test-only compatibility fix.
The published tag and assets are immutable; main is not misrepresented as the
source from which the signed DMG was built.

## Release-process disposition

The earlier independent-DVT checklist was more extensive than the acceptance
evidence collected. This release uses the documented maintainer-acceptance
exception in RELEASING.md, not a fabricated fifteen-row independent PASS.
Unwitnessed tests remain unwitnessed. The dedicated production acceptance and
metadata assets record this basis and the immutable candidate identities.
Final SHA256SUMS is download-integrity evidence, not a certification of testing.

Repository preparation includes private vulnerability reporting, Issues,
Discussions, triage labels, and protection of main requiring review and both
CI checks, with force pushes and deletion blocked. Actual settings are verified
at publication; they are not properties of the installed app.

No source-code or installer change is part of this promotion. Future fixes
must use a new release version rather than replacing these downloads.
