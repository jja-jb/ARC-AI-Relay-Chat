# ARC 2.5 release checklist

- [ ] Complete the two-window recovery/resize/scroll/focus and history-page
  acceptance plan in `docs/ARC_2_5_TEST_REVIEW.md` on the frozen candidate.
  No repeated-constraint warnings or unresponsive window are acceptable.

- Verify bounded returning-poll recovery and the explicit reconnect/copy control.
- Verify completed evidence correction, immutable history, reopening capacity,
  timestamp plausibility, stale revisions and exact replay.
- Reconcile docs/ARC_2_2_TEST_REVIEW.md and distinguish local checks from pending
  independent acceptance. Verify Terse 2.1 / wire 3 repair semantics, wire-2
  history preservation and fresh declarations after upgrade. Do not label
  instructions for silent observers as enforced transport restrictions.

The release procedure is [docs/RELEASING.md](docs/RELEASING.md). This checklist
does not replace it.

## Source

- [ ] Version, changelog, specifications, help, man page, and app agree.
- [ ] Hummingbird LICENSE SHA-256 is
      `988a906412af48c37e35fc3272402818677d31572fb65ea931aa98f21e003c24`.
- [ ] `make clean check` passes without network access.
- [ ] Source tree and index are clean; no ignored ambient file enters an asset.
- [ ] Generated DMGs, archives, PDFs, manifests, reports, metadata, and
      checksums are release assets outside the tagged source tree.
- [ ] `docs/TRACEABILITY.md` names every normative requirement.
- [ ] Annotated release tag resolves to the reviewed commit.

## Public repository before general availability

- [ ] Use the existing `jja-jb/ARC-AI-Relay-Chat` repository, as selected by the
      maintainer for final testing. Verify the pushed tag matches the reviewed
      frozen candidate; do not rewrite the tag or substitute a newer main tree.
- [ ] From a logged-out browser and an unauthenticated fresh clone, verify the
      README, local links, and complete reviewed file inventory.
- [ ] Set `brand/arc-social-preview.png` as the repository social preview.
- [ ] Enable Issues, Discussions, and Private Vulnerability Reporting; create
      the `bug`, `enhancement`, and `triage` labels; verify the private-report
      link.
- [ ] Protect `main`: require review, `Native check / macos-15`, and
      `Apple silicon app`; block force pushes and branch deletion.

## Mac candidate

- [ ] App and `arc` are arm64-only.
- [ ] Bundle identifier is `org.jonnybass.arc`; version is `2.5.0`.
- [ ] Privacy manifest declares no collection/tracking and the exact approved
      file-metadata and elapsed-time reasons.
- [ ] Install manifest contains only regular native command, knowledge,
      specifications, and legal files.
- [ ] Developer ID signatures, notarization, and staples pass verification.
- [ ] DMG contains only ARC.app and the Applications link.

## Evidence

- [ ] Prepared DMG, source archive, literature PDF, and manifest are frozen before DVT.
- [ ] Independent DVT passes on a clean Apple silicon Mac against the
      exact prepared hashes.
- [ ] Final DVT report has no blank, blocked, skipped, or failed required row.
- [ ] DVT identifies independent tester, start/finish, the Apple silicon Mac,
      system, toolchain, every prepared hash, and no unresolved deviation.
- [ ] Final metadata binds the report; SHA256SUMS covers the other six assets.
- [ ] `release-check` re-reads canonical metadata and all seven final assets.
- [ ] A maintainer reviews the release page for factual, modest language.

## Publication

- [ ] Publish only the tested bytes; do not rebuild after DVT.
- [ ] Attach all seven assets and verify downloaded hashes.
- [ ] Keep signing credentials and notarization profiles out of source and
      release assets.
