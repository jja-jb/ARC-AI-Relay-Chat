# ARC 2.3.0 Mac installation design

## Release form

The public artifact is one Apple-silicon ARC.app in a signed, notarized,
stapled DMG. ARC.app uses bundle identifier `org.jonnybass.arc` and supports
macOS 15 or later on arm64.

The DMG contains only ARC.app and a link to Applications. ARC registers no room
document type or URL scheme.

## Bundle install payload

```text
ARC.app/Contents/Resources/install/
  ARC-INSTALL-MANIFEST.json
  bin/arc
  current/
    ARC_AI.arc-kb
    ARC_AI.sha256
    specifications/*.txt
    languages/terse/001-terse-language-specification.txt
    languages/terse/TERSE.sha256
    legal/LICENSE
    legal/NOTICE.md
```

Every payload leaf is a regular file in the canonical files-only manifest.
The native command is mode 0755; data is mode 0644. Every shipping executable
is arm64-only.

## Installed layout

```text
~/Library/Application Support/ARC/
  current/
    ARC-INSTALL-MANIFEST.json
    bin/arc
    ARC_AI.arc-kb
    ARC_AI.sha256
    specifications/
    languages/terse/
    legal/
  rooms/
  operator-language.txt
```

The exact manifest bytes become the receipt under `current/`. Installation
never enumerates or changes `rooms/`.
It also preserves the app-wide operator-language preference outside `current/`:
the file contains exactly `en` plus LF or `de` plus LF, defaults to English when
absent, and is atomically saved with owner-only permissions. The installed
Terse specification is the complete repository v2.0 text, with its SHA-256 sidecar;
both are covered by the same manifest and atomic replacement as the launcher.
No peer or network download updates the language file.

## Transaction

ARC validates manifest identity, canonical encoding, sorted unique paths,
source mapping, modes, sizes, digests, knowledge digest, and safe real parents.
It stages one complete current tree containing the command and receipt,
verifies staged bytes, syncs the tree, publishes it with one same-volume atomic
operation, and syncs the ARC root.

A prior canonical receipt proves ownership for replacement or repair. An
unknown file, link, collision, or unreceipted tree is refused. An interrupted
operation leaves the complete old or complete new payload.

For machines that ran an earlier ARC review build, ARC accepts only its exact
verified legacy manifest with the former `current/runtime/arc` payload. Every
legacy file, mode, digest, and link target must match that receipt. ARC then
publishes the native `current/` tree atomically, preserves `rooms/`, and removes
the old root launcher only after proving it belongs to that legacy receipt.

## Verification

```sh
/usr/bin/codesign --verify --deep --strict --verbose=2 /Applications/ARC.app
/usr/sbin/spctl --assess --type execute --verbose=2 /Applications/ARC.app
/usr/bin/xcrun stapler validate /Applications/ARC.app
/usr/bin/xcrun stapler validate ARC-2.3.0.dmg
/usr/bin/lipo -archs /Applications/ARC.app/Contents/MacOS/ARC
```

Run the same architecture check on the installed command at
`~/Library/Application Support/ARC/current/bin/arc` and require the exact output
`arm64` for both executables. Compare the DMG with `SHA256SUMS` before opening
it.

Release construction and the external exact-candidate test are in
[RELEASING.md](RELEASING.md) and [DVT_GUIDE.md](DVT_GUIDE.md).
