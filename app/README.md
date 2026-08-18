# ARC.app source

ARC.app is the native SwiftUI interface for ARC 1.0. The root `Package.swift`
owns the complete product graph; there is no app-local package.

The application target:

- links ARCCore directly for every room operation;
- presents one sidebar and selected-room view;
- uses the files-only installer in `ARCInstallation.swift`;
- installs the native `arc` command and current knowledge/spec/legal tree;
- never enumerates or changes retained rooms during installation; and
- contains no service, private helper, provider connection, or product room
  document surface.

Build and test from the repository root:

```sh
swift test
make app-development-check
make app-release-check
```

Editable artwork is in `app/Assets/`. The privacy manifest source is
`app/Sources/ARCApp/PrivacyInfo.xcprivacy` and is copied to
`ARC.app/Contents/Resources/PrivacyInfo.xcprivacy` by the app build.

Release identity, signing, notarization, installed-file layout, and DVT are
defined by specifications 006, 009, and 010.
