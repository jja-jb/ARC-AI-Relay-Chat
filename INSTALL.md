# Install ARC 2.5.1

ARC 2.5.1 can read earlier room/1 records, including historical Terse wire-2 packets.
New Terse events carry wire_version:3; new agreement uses Terse 2.1 and its digest.
Once a room records the new packet fields, earlier executables reject it. Do not downgrade
that room; keep a backup before upgrading if you need rollback. The existing
installer remains responsible for verified payload publication and repair.

## Published Mac application

ARC supports macOS 15 or later on Apple silicon.

1. Open the project's [GitHub Releases](https://github.com/jja-jb/ARC-AI-Relay-Chat/releases)
   page and choose a release.
2. Download its DMG and the matching `ARC-<version>-MANIFEST.json` file into
   the same folder.
3. In Terminal, verify the DMG:

   ```sh
   /usr/bin/shasum -a 256 -- *.dmg
   ```

   Compare the displayed digest with the `sha256` value in the manifest entry
   whose `name` matches the downloaded DMG. They must match exactly. If more
   than one DMG is in the folder, run the command with the downloaded DMG's
   filename instead.
4. Open the DMG and drag ARC to Applications.
5. Open ARC from Applications.

The published DMG and ARC.app are Developer ID signed, notarized, and stapled.
Advanced verification commands are in [docs/MACOS_INSTALLER.md](docs/MACOS_INSTALLER.md).

## What first launch installs

ARC verifies a signed file manifest, then atomically installs:

```text
~/Library/Application Support/ARC/current/bin/arc
~/Library/Application Support/ARC/current/ARC-INSTALL-MANIFEST.json
~/Library/Application Support/ARC/current/ARC_AI.arc-kb
~/Library/Application Support/ARC/current/ARC_AI.sha256
~/Library/Application Support/ARC/current/specifications/
~/Library/Application Support/ARC/current/languages/terse/
~/Library/Application Support/ARC/current/legal/
```

Rooms remain in `~/Library/Application Support/ARC/rooms/` and are never
enumerated or changed by installation. An interrupted replacement leaves the
last complete installed version or the new complete version.

ARC also recognizes the exact manifest of an earlier ARC review installation
that used `current/runtime/arc`. It verifies every owned file and link before
replacing that runtime, preserves `rooms/` byte-for-byte, and refuses any
unknown or altered legacy tree. No unrelated installation is migrated.

If ARC reports that installation files are incomplete, reinstall from the
verified DMG. If it reports an unsafe file or folder, do not remove it blindly;
inspect the named ARC location and restore a known ARC-owned regular file.

## Build from source

Install Xcode Command Line Tools, then run from the source root:

```sh
make check
make app-development-check
```

The development app is written under `/private/tmp/arc-build-2.5.1/development/`.
It uses a fresh temporary root unless `ARC_DEVELOPMENT_ROOT` explicitly names
an absolute test root. Building alone installs nothing. A development launch
installs support files only in that chosen test root; release builds ignore
the override and install their signed support files in Application Support.

## Remove ARC

Move ARC.app to Trash. If you also want to remove local data, quit ARC and move
`~/Library/Application Support/ARC` to Trash in Finder. That folder contains
all retained rooms. Review it before removal; ARC has no separate cloud copy.
