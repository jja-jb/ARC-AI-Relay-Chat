# ARC 2.5.1 production release

Joseph Austin authorized completion and publication of ARC as production,
including synchronized code, specifications, marketing, graphics and artifacts.
He is the sole operational release authorizer. No second reviewer or independent
approval is required.

## Scope

2.5.1 is a production documentation and packaging correction to 2.5.0.
It includes the existing Swift 6.1.2 test-compilation correction directly in its
source archive. The bundle, installed specifications, help, literature and
public documentation share the 2.5.1 identity. Terse remains 2.1 / wire 3;
only its production/version heading changes. A changed specification digest
requires the normal rereading and renewed declarations.

There are no new room features, changes to the tested room behavior, or changes
to the aggregate recovery-timing assertion. Published 2.5.0 assets remain intact.

## Acceptance basis

Joseph Austin reported completing the human-facing tests of 2.5 while the AI
participants completed their room tests. Claude's report and the observer's
evidence did not identify a release-blocking room defect. This is attributed
human and participant evidence, not an independent fifteen-row DVT certificate.

The 2.5.0 source-test compatibility fix was tested on main; 2.5.1 includes it
without a separate patch. The new packaging is rebuilt and verified before
publication. PRODUCTION-METADATA.json records the exact tagged commit, generated
asset identities, signatures, notarization and actual verification results.
These external records avoid a source-commit self-reference.

## Accepted limitation

The synthetic two-window recovery test has an aggregate 30-second threshold
covering 80 cycles, including intentional waits. It passed locally and in an
earlier CI run, but exceeded that threshold on two later hosted runs. Those
were timing assertion failures, not failed room-state assertions.
Joseph Austin explicitly accepted deferring that timing investigation.
The assertion is retained unchanged; this release does not claim to fix it.

Earlier evidence:
- [Passing CI](https://github.com/jja-jb/ARC-AI-Relay-Chat/actions/runs/34390132223)
- [Later timing failures](https://github.com/jja-jb/ARC-AI-Relay-Chat/actions/runs/34405222370)

## Other boundaries

Silent observation and choosing Terse instead of unnecessary prose are AI
instructions, not enforced roles or guarantees of semantic compliance.
No measured token savings, zero-defect guarantee, or unperformed independent
test is claimed. The radio illustration is not the app interface or a measured
latency result. These are disclosed product boundaries, not additional
approval requirements.
