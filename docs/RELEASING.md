# Releasing ARC 3.2.2

## Authority and evidence

Joseph Austin alone authorizes publication. Tests and reviews inform his
decision; no independent reviewer or second person's approval is required.
Record failures, unrun checks and accepted limitations accurately. Never turn
an accepted exception into a fabricated PASS.

ARC 3.2.2 ships Quinby's Corner. The build must include its verified canon seed,
portrait, specification and digest, plus the existing ordinary-room payload.
Run the Corner tests alongside ordinary-room regressions. A local build is not
a published release; record signing, notarization, source identity, and actual
validation separately before distribution. Earlier production records remain
historical evidence for their original versions.

## Build and freeze

Use macOS 15 or later, Apple silicon, and Xcode Command Line Tools.
Use the clean annotated v3.2.2 tag. Keep generated assets outside the checkout.
The controlling LICENSE digest remains
988a906412af48c37e35fc3272402818677d31572fb65ea931aa98f21e003c24.

Run build targets sequentially:

```sh
make check
make app-release-check
make release-prepare \
  SIGNING_IDENTITY="Developer ID Application: AUTHORIZED IDENTITY" \
  NOTARY_PROFILE="authorized-keychain-profile" \
  LITERATURE_PDF=/absolute/path/ARC_AI_Relay_Chat_Literature.pdf
```

Generate the literature from brand/arc-product-brief.html and visually inspect
both pages. The brand manifest verifies the editable input and public graphics.
No separate source-compatibility patch belongs in this release.

Preparation verifies the clean annotated tag, builds and checks native products,
signs and notarizes the command-containing app, staples it, creates and signs the
DMG, notarizes and staples the DMG, archives the exact tag, and writes the four
prepared assets under /private/tmp/arc-output-3.2.2/candidate/ARC-3.2.2.
Signing credentials stay in the Keychain or release environment, never source.

## Production verification and records

Mount the prepared DMG read-only. Verify the app and command signatures,
arm64-only architectures, bundle version and identifier, Gatekeeper acceptance,
notarization and staples, privacy and installed-file manifests, knowledge and
Terse digests, and exact bundled specification and legal bytes. Do not install
over a user's app just to perform these checks. Detach the image after checking.

Verify the source archive is the exact annotated-tag tree and includes the
current source, tests, docs, specifications and graphics. Rebuild from the
archive using the documented non-Git checks. The archive's source-archive-test
correctly refuses without Git metadata; verify that check from the tagged Git
checkout. Record actual results, including any accepted timing-test exception.

Publish seven production assets:

- ARC-3.2.2.dmg
- ARC-3.2.2-source.tar.gz
- ARC_AI_Relay_Chat_Literature.pdf
- ARC-3.2.2-MANIFEST.json
- PRODUCTION-ACCEPTANCE.md
- PRODUCTION-METADATA.json
- SHA256SUMS

Copy the production decision into PRODUCTION-ACCEPTANCE.md. Generate metadata
with schema arc.maintainer-production-acceptance/1, the exact version, tag,
commit, acceptance basis, actual verification results, signer, Apple submission
identifiers, knowledge and Terse digests, and each payload's size and SHA-256.
Identify this as maintainer acceptance, not independent DVT certification.
SHA256SUMS covers every other asset in bytewise filename order.

## Optional independent verification

The strict release-dvt, release-seal and release-check tools remain available
when Joseph Austin chooses the independent report format in
[DVT_GUIDE.md](DVT_GUIDE.md). Their strict report rules are not weakened.
They produce their own DVT report and RELEASE-METADATA.json instead of the
maintainer-acceptance records. An unperformed strict procedure is not a
publication veto and must not be described as having passed.

## Publish and verify

Push the exact source and annotated tag. Keep main protected against force
pushes and deletion. No required second-reviewer rule belongs in this project.
Use CI as evidence; record an explicitly accepted exception rather than hiding
a failed result. Build tooling itself does not publish.

On Joseph Austin's authorization, publish the identified assets as a production
GitHub Release and mark it Latest. Compare every downloaded asset with the local
copy and checksum list. Verify the source tag, main, public download links,
release status and source inventory. Never move a published tag or replace a
published download; corrections use a new patch version.
