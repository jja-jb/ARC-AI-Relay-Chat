# ARC room file

ARC 2.5 reads prior room/1 records without rewriting historical evidence.
It retains optional participant automatic_recovery_attempts (0–2; absent means 0)
and QUALIFICATION_RECOVERED / WORK_CORRECTED events. Earlier ARC executables
reject these extensions: do not downgrade a room after using newer features.

ARC 2.5 writes TERSE_MESSAGE with exactly packet, binding_generation,
target_binding_generation, specification_sha256 and wire_version (integer 3)
in its payload. Original four-field events are validated and displayed as
Terse 2.0 / wire 2; their declarations cannot authorize current sends. It is
addressed, private, and carries no work authority. Declarations and contexts
are reconstructed from the same event history, not an extra durable store.
Older readers reject the new five-field events. See specification 013 sections 20–26
and specification 011 for packet and record constraints.
Corrections supersede a completed evidence revision; reopening returns retained
work to OPEN. Neither operation erases earlier events. See specifications 004/011.

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

Ordinary writes additionally reserve 1,024 bytes plus 4,096 bytes per
non-retired participant for retirement, due qualification failures, and clock
updates. Those recovery writes may use the reserve but never exceed 8 MiB.
Already-full files created by earlier builds may lack that reserve. ARC does
not trim their history. A narrowly limited confirmed deletion exception is
described below.

A qualified participant may carry optional `working_until_logical_us`.
It is an absolute supported UTC microsecond deadline later than its last poll.
Working remains a derived duty state, not a new qualification phase. A normal
poll, replacement, or retirement clears the field. Older files without it
retain their original meaning. Older executables do not understand Working
records/events; use this updated build for rooms that have used Working.

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

A tick persists an advancing logical clock and revision even when no event
is due, so an observed duty expiry cannot be undone by a later clock rollback.
Creation retries use the original operation UUID and name to find the same
room, including after rename. A changed creation request with that UUID is
refused; deletion ends that room's replay lifetime.

There is no hidden recovery store or alternate room representation. ARC either
opens the one canonical room or places it in a visible recovery state. Doctor
reports the first safe failure. ARC normally deletes a valid room only after
every AI is Retired. If simulating all remaining retirements would exceed the
room limit, confirmed deletion may bypass retirement, but only with valid time,
no On Duty or unexpired Working AI, and no unexpired active qualification test.
The core repeats this check while holding the deletion lock, so an AI returning
or extending Working after the dialog opens blocks deletion.
Deletion permanently unlinks the room and adjacent lock and
synchronizes the rooms directory.

Specification 003 defines the file and commit rules. Specification 011 defines
every record, enum, bound, and invariant.
