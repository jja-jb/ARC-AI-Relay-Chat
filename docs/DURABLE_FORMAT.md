# ARC room file

Each ARC room is one private, human-readable file:

```text
~/Library/Application Support/ARC/rooms/<Room ID>.arcroom
```

The filename Room ID and the embedded `room.id` must match. The file is a
regular 0600 file, at most 8 MiB, containing canonical UTF-8 JSON followed by
one LF. Object keys are sorted, strings use NFC text, numbers are bounded
integers, and unknown, missing, duplicate, noncanonical, or structurally invalid
content is refused.

## Top-level shape

```json
{
  "activity": [],
  "format": "arc.room/1",
  "participants": [],
  "room": {},
  "work": []
}
```

`room` contains the name and safe ID, created and updated UTC times, revision,
next Activity sequence, current Producer and generation, logical wall time, and
the latest Administrator operation replay record. `participants` contains up
to 64 lifecycle, binding, qualification, check-in, and operation replay
records. `work` contains up to 50 non-COMPLETE records and 256 retained records.
`activity` is the complete coordination history for the room's lifetime.

Activity begins at sequence 1, remains contiguous, and is never pruned while
the room exists. The 8 MiB room limit is fail-closed: ARC refuses a mutation
that would exceed it, leaving the prior complete room unchanged. Activity is a
durable coordination record, not a cryptographic journal.

## Lock and atomic update

Each room has one adjacent stable lock file:

```text
<Room ID>.arcroom.lock
```

It is a zero-byte 0600 regular file. It contains no room state and is not
removed during ordinary room operations, so concurrent waiters cannot split
across different lock inodes. ARC holds `flock` only for one bounded read or
mutation and returns `BUSY` after five seconds.

A mutation writes a new 0600 temporary regular file in the rooms directory,
synchronizes it, renames it atomically over the prior room, and synchronizes the
directory. Failure before rename leaves the old room; failure after rename
leaves the complete new room. Startup ignores incomplete hidden temporary
files. ARC refuses linked parents, room links, lock links, special files, and
filename/identity mismatches.

## Time and recovery

Durable time is UTC epoch microseconds from the Mac wall clock. A mutation uses
the greater of the sampled time and the room's last logical time, so equal or
backward wall samples never move room time backward. An unusable sample refuses
AI actions, polling, qualification retry, Producer selection, and room creation
as `CLOCK_UNAVAILABLE`; ARC does not invent a check-in. Rename, invite,
instruction replacement, and retirement remain available to the Administrator
using the last stored logical time and mark their Activity time unverified.
Read views say `TIME_UNAVAILABLE` when time cannot be sampled.

There is no hidden recovery store or alternate room representation. ARC either
opens the one canonical room or places it in a visible recovery state. Doctor
reports the first safe failure. ARC deletes only a valid room after every AI is
Retired. Deletion permanently unlinks the room and adjacent lock and
synchronizes the rooms directory.

Specification 003 defines the file and commit rules. Specification 011 defines
every record, enum, bound, and invariant.
