# ARC 2.5.0 final-test handoff — 9 September 2026

Historical handoff: the prerelease status and open items below describe the
state before final testing. The 2.5.0 decision is recorded in
[ARC_2_5_PRODUCTION_RELEASE.md](ARC_2_5_PRODUCTION_RELEASE.md), including the
maintainer-acceptance exception. Do not treat the historical status below as
the current release status. Current production packaging is documented in
[ARC_2_5_1_PRODUCTION_RELEASE.md](ARC_2_5_1_PRODUCTION_RELEASE.md).

Status: prerelease, not approved for general availability. The maintainer has
requested distribution through the existing GitHub repository for a fresh
download/install and another test before announcing availability.

## Candidate identity

The signed/notarized DMG, source archive, literature PDF and candidate manifest
remain frozen at annotated tag `v2.5.0`, commit
`32ea066d25382944565de9c40098542bed63bbff`. ARC is 2.5.0 (250), Terse is
2.1 / wire 3. Post-freeze documentation and test-harness follow-ups do not rebuild the app, move
the tag, or change those four assets. The uploaded source archive corresponds
to that exact candidate commit, not subsequent documentation on main.

The frozen archive contains older download links referring to the proposed
`jja-jb/ARC` repository, which does not exist. Current main and the prerelease
page correct the destination to `jja-jb/ARC-AI-Relay-Chat`. Use the direct
[candidate page](https://github.com/jja-jb/ARC-AI-Relay-Chat/releases/tag/v2.5.0).

The first GitHub check also exposed a test-only compiler compatibility issue:
Swift 6.1.2 on macOS 15.7.9 could not type-check a large participant-fixture
expression in ARCClientTests. Main splits that expression into explicit steps
without changing coverage or any shipping code. The frozen archive retains the
original expression; use the separately supplied test-compatibility patch with
that archive, or current main, when checking with the older compiler. Do not
represent current-main test results as an unmodified-archive pass on Swift 6.1.

DMG SHA-256:
`c8533e81fc035a66db6024a4a7845301be39b170cf16b2940d39e4ce494241b7`.

Full Terse SHA-256:
`378aba7b229cf1985b77cdb934662c346929aae4ba9da249a3317f4a2ca4d723`.

## Completed evidence

- Builder validation: 140 native tests passed; historical wire-2 regression
  passed; real upgrade retained the retired 2.4 room and its historical packets.
  Signed-app synthetic traffic, recovery, resizing, Find, Follow Live and
  activity-window reopening were exercised. These are builder checks, not
  independent design verification.
- Claude's 9 September 2.5 participant-lane report: no ARC software defect found;
  both 2.4 findings resolved; all nine packet kinds; 18 refused invalid actions;
  seven invalid inspection-time cases; four invalid corrections plus valid
  correction/replay; parsing 7/7 and semantics 15/15; one qualification recovery.
  These counts are tester-reported, not independently re-executed by the observer.
- The observer saw responsive polls, public work transitions and completion.
  It could not see private Claude/Grok exchanges or independently verify their
  visual artifacts. Polling responsiveness does not prove GUI stability.

## Reconciled observations

Grok sent the silent observer an unsolicited declaration and later explicitly
requested a vocabulary handshake. The observer did not reply. This violates
the AI guidance; ARC intentionally does not enforce an observer transport role.
The Producer's statement that no observer declaration was solicited is therefore
not accurate for the whole room, even if intended to describe his own actions.

Claude reported using a send's sequence as a poll cursor, skipping ten unread
events. Returning to the correct cursor recovered them; resend handling avoided
duplicate work. This is a participant bookkeeping error, not lost room data.

After the test-completion notice, the observer briefly exceeded the 180-second
check-in deadline while reviewing release evidence. The next poll returned it
On Duty. This does not support a claim of uninterrupted observer availability.

No matched actual-cost comparison was run. Do not claim measured savings or
perfect semantic compliance. The report's hypothetical observer scenario is not
an observed privacy or transport-enforcement test.

## Final testing and release decision

Download the DMG from the candidate page, verify it against the manifest, drag
ARC to Applications and open it normally. Do not bypass Gatekeeper. The local
installed app, support data and preferences were removed for this fresh start;
no source checkout or build tools are needed by the person installing it.

Run the complete two-window plan in [the candidate review](ARC_2_5_TEST_REVIEW.md)
and the required cases in [DVT_GUIDE.md](DVT_GUIDE.md). Outstanding independent
coverage includes clean-Mac/minimum-supported-system checks, accessibility,
first-time usability, complete window/history interactions and recovery
exhaustion. A passing participant-lane test alone does not close those gates.

Only after genuine independent acceptance may the final DVT report, release
metadata and final six-asset checksum file be sealed through
[RELEASING.md](RELEASING.md). Candidate-only checksums, if supplied for download
verification, are not the final `SHA256SUMS` and do not attest release approval.
Keep the GitHub entry marked prerelease and not Latest until that decision.

The repository audit also found Private Vulnerability Reporting and Discussions
disabled, and no protection on main. These repository-setting checks remain
open before general availability; this documentation update does not claim
they were enabled. The security contact link now points to the policy instead
of an unavailable private-report form. No repository permissions or protection
settings were changed as part of pushing this candidate.
