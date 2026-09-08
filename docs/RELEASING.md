# Releasing ARC 1.0

This procedure freezes and records an already complete product. It does not
publish, upload, push, or create a tag.

## Requirements

Use macOS 15 or later with Xcode Command Line Tools. Start from a clean checkout
whose `HEAD` is the reviewed annotated `v1.1.0` tag. The source build has no remote
package dependency and performs no network access. Signing and notarization are
the only steps that contact Apple.

Verify the Hummingbird License:

```sh
shasum -a 256 LICENSE
```

The result must be:

```text
988a906412af48c37e35fc3272402818677d31572fb65ea931aa98f21e003c24
```

Then run:

```sh
make clean
make check
make app-release-check
```

Both shipping executables must be arm64-only. The app check
also validates the bundle identity, privacy manifest, exact files-only install
manifest, knowledge digest, specifications, and legal payload.

## Freeze the candidate

Store the Developer ID identity and notarytool profile in the Keychain or your
release environment, never in this repository. Run:

```sh
make release-prepare \
  SIGNING_IDENTITY="Developer ID Application: REVIEWED IDENTITY" \
  NOTARY_PROFILE="reviewed-keychain-profile" \
  LITERATURE_PDF=/absolute/path/ARC_AI_Relay_Chat_Literature.pdf
```

The target independently checks the tag and clean tree, runs all local checks,
builds Apple-silicon executables, signs the native command and app, notarizes and
staples the app, creates and signs the DMG, notarizes and staples the DMG, makes
an archive from the exact tag, and writes:

```text
output/candidate/ARC-1.1.0/ARC-1.1.0.dmg
output/candidate/ARC-1.1.0/ARC-1.1.0-source.tar.gz
output/candidate/ARC-1.1.0/ARC_AI_Relay_Chat_Literature.pdf
output/candidate/ARC-1.1.0/ARC-1.1.0-MANIFEST.json
```

The candidate manifest records the immutable DMG, source, and literature names,
sizes, and SHA-256 values together with the tag, commit, architectures, minimum
macOS, knowledge identity, and Hummingbird License identity. Do not change any
candidate byte after this point.

## External DVT

Give the exact candidate to an independent tester. Follow
[DVT_GUIDE.md](DVT_GUIDE.md) on a clean Apple silicon Mac. Copy
[DVT_REPORT_TEMPLATE.md](DVT_REPORT_TEMPLATE.md) to a plain-text path outside
the checkout, complete every field and evidence row, and run:

```sh
make release-dvt \
  DVT_REPORT=/absolute/path/ARC-1.1.0-DVT-REPORT.txt
```

A changed candidate, mismatched commit, unfinished evidence, non-PASS row,
unidentified-machine report, or malformed report stops the release.

## Seal the release records

Every mounted-candidate validation step must succeed before sealing can run.
The check stops at the first failure; unmount cleanup must not turn a failed
app, signature, architecture, archive, or source check into a successful gate.

After DVT passes, run:

```sh
make release-seal \
  SIGNING_IDENTITY="Developer ID Application: REVIEWED IDENTITY" \
  NOTARY_PROFILE="reviewed-keychain-profile" \
  LITERATURE_PDF=/absolute/path/ARC_AI_Relay_Chat_Literature.pdf \
  DVT_REPORT=/absolute/path/ARC-1.1.0-DVT-REPORT.txt
```

This repeats the clean-tag and DVT binding checks and writes exactly seven public
assets under `output/release/ARC-1.1.0/`:

```text
ARC-1.1.0.dmg
ARC-1.1.0-source.tar.gz
ARC_AI_Relay_Chat_Literature.pdf
ARC-1.1.0-MANIFEST.json
ARC-1.1.0-DVT-REPORT.txt
RELEASE-METADATA.json
SHA256SUMS
```

Release metadata records the signer, Apple notarization identifiers, knowledge
and license identities, tester and test time, tag and commit, bundle identity,
architectures, and final PASS. `SHA256SUMS` covers the other six files in
bytewise filename order.

## Human publication

Before publishing, a maintainer who did not perform the seal compares all seven
files with the records, verifies the logged-out repository view and security
contact, and reviews the release page for factual, modest language. Publish the
tested bytes once. Compare downloaded assets with `SHA256SUMS`. Never replace a
published tag or asset; use a new patch version for a correction.
