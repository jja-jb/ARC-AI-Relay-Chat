# ARC 2.2 architecture

ARC has one small native architecture:

```text
ARC.app ───────┐
               ├── ARCCore ── one rooms/<RoomID>.arcroom JSON record
native arc ────┘       │
                       └── ARCKnowledge ── ARC_AI.arc-kb
```

ARC.app calls ARCCore directly for human operations. The native `arc` command
calls the same ARCCore for AI operations. There is no service, hidden helper,
provider connection, alternate core, or second durable projection.

## Source graph

- `Package.swift` — the complete build graph, with no remote dependency.
- `app/Sources/ARCApp/` — SwiftUI application and atomic installed-file adapter.
- `app/Sources/ARCCommand/` — strict public command parser and JSON envelopes.
- `app/Sources/ARCCore/` — room rules, canonical JSON codec, file publication,
  qualification, duty, messages, work, Activity, and knowledge access.
- `knowledge/` — fixed-workspace C knowledge validator and tests.
- `Sources/ARCDevTool/` — deterministic knowledge and release chores used only
  from a source tree.
- `10_specs/platform_support/` — thirteen core specifications, 000–012.
- `languages/terse/` — the full governing Terse v1.0 specification, 013.

## Durable state

Each room's authority is one bounded canonical JSON file:

```text
~/Library/Application Support/ARC/rooms/room-xxxxxxxxxxxx.arcroom
```

An adjacent zero-byte `.lock` file holds no room state; its stable inode only
serializes local readers and writers. A mutation reads one complete validated
revision, constructs one complete next revision, writes and synchronizes a
same-directory temporary file, then atomically replaces the room. The old file
is never edited in place.

Activity is the complete visible room history for the room's lifetime.
Sequence numbers never reset. ARC never silently removes, truncates,
summarizes, or replaces an older event. Participant and work state
remain explicit arrays in the same room record.

## Authority

The human is Administrator, never Producer. Every AI call names its Room ID,
participant ID, and current binding. Producer actions also carry the observed
Producer generation; work updates carry the observed work revision. Those
facts are checked in the same locked room revision as the change.

## Knowledge

The C reader receives an immutable pointer, exact length, expected SHA-256, and
a fixed 16 KiB workspace. It exposes only typed members through copied text.
It has no pathname or generic lookup API. `arc-dev` deterministically builds,
validates, deconstructs, and reconstructs the same format for source review.
The full Terse specification is a separate signed file with its own SHA-256
sidecar, read through the same bounded-file verification used by polling.
`arc spec read 013` returns that full text; it is not a Profile 1 member.

## Boundaries

ARC is local and offline. Text is inert data. It trusts the current macOS
account and does not authenticate providers. It supports up to 64 AI
participants; at least two available qualified AIs with an available Producer
are required for Active. Available means On Duty or Working before its deadline.

Exact fields, operations, limits, errors, and byte formats are in
[specifications 000–013](10_specs/platform_support/001-shared-how-to-read-these-specs.txt).
