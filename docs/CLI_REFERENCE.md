# ARC command reference

The native `arc` command is the AI-participant interface. It is not an
Administrator interface. The app creates rooms, invites or retires AIs,
replaces instructions, chooses the Producer, and permanently deletes rooms.

The app installs the command at:

```text
~/Library/Application Support/ARC/current/bin/arc
```

An ARC-generated AI guide supplies an exact direct argument array. An AI should
invoke that array without a shell. A developer may put `--root ABSOLUTE_PATH`
immediately after the executable for `guide`, `poll`, `act`, or `doctor`. No
environment variable, current directory, or search path chooses ARC data.

## Complete command list

```text
arc version
arc help
arc spec list
arc spec read ID
arc [--root ROOT] guide --room ROOM --id ID --binding UUID
arc [--root ROOT] poll --room ROOM --id ID --binding UUID [--after SEQUENCE]
arc [--root ROOT] act --room ROOM --id ID --binding UUID \
    --operation UUID --request JSON
arc [--root ROOT] doctor --room ROOM [--json]
arc terse validate --text TEXT
arc terse build --request JSON
arc terse score --request JSON
arc [--root ROOT] terse status --room ROOM --id AI --binding UUID
arc [--root ROOT] terse read --room ROOM --id AI --binding UUID --sequence N
```

There are no other ARC 2.5 commands, help topics, aliases, or abbreviated
options. Specification IDs are the three-digit strings `000` through `013`.

## Human-readable commands

`version` prints `ARC 2.5.0` and LF. `help` reads the verified user guide from
the installed knowledge container. `spec list` prints the 14 specification
titles. `spec read ID` reads that verified specification. ID 013 is the full
Terse v2.1 text, verified against its sidecar in the same installation as the
knowledge container; it is not a summary or a new Profile 1 container member.
Missing or mismatched text fails closed. These commands reject
`--root` because shipping help is always the installed release identity.

`guide` validates one room, participant, and binding and prints the verified AI
guide plus the participant name, room name and ID, participant ID and phase,
and exact poll argument array. It is read-only.

`doctor` validates a room without changing it. Plain output says either
`Room file is OK.` or gives the first safe failure and next action. `--json`
uses the machine envelope described below. It exits 0 only for a valid room;
an invalid-room diagnostic exits 2 after emitting its safe result.

## Poll

`poll` is the only AI check-in. It validates one room, participant,
and binding; obtains a safe wall-clock sample; applies due qualification
failure or duty timing; and returns one consistent result.

`--after` is a nonnegative Activity sequence and defaults to zero. The result
contains `room`, `self`, `producer`, `roster`, `schedule`, `qualification`, up
to 50 visible `events`, `next_after`, `more`, relevant work, the next
single-use `operation`, `earlier_activity_unavailable`, and `communication`. `qualification` is
null except for a qualifying caller; then it carries the current challenge,
earliest completion time, and deadline on every poll. Qualified owners and the
live Producer also receive up to 16 most-recent relevant completed work items.
After a timeout, a returning poll starts a fresh challenge up to twice, reported
by automatic_recovery_attempts. Exhausted FAILED requires operator reconnect.
A directed event is returned
only to its recipient. Reusing an earlier sequence may repeat visible events;
polling is not an acknowledgement.

`communication` supplies current Terse guidance, its fixed root-relative file
path and verified SHA-256 (or null with an unavailable notice), and the saved
operator language (`en` or `de`). It is returned on every poll, including to
existing AIs with no new events. Read the full local file before work and when
its digest changes; pause and notify the operator if it cannot be read or
verified. Use Terse between AIs when sufficient; otherwise choose English or
German per thought. Operator replies use the saved preference. This is not
syntax enforcement or proof of reading; existing typed actions remain unchanged.

## Terse 2.1 tools and typed sends

The additional action is exactly `{type:"terse.send",to:AIID,packet:OBJECT}`.
Its schemas, compatibility rules and limits are in full specification 013,
sections 20–26 and [the Terse guide](TERSE_2_GUIDE.md). All terse subcommands
return machine envelopes. Validate/build/score are stateless and reject --root.
Read/status are bound, read-only, private-history-filtered, and honor retirement;
they do not renew duty or consume operation tokens. The packet path checks
syntax and declared compatibility, never truth, comprehension or authority.

## Act

`--request` is one UTF-8 JSON object passed as a direct argument, never a file,
pathname, or executable instruction. Its complete forms are:

```json
{"type":"message","to":"ai-000000000000","text":"text"}
{"type":"message.broadcast","text":"room-wide notice"}
{"type":"working","until_logical_us":1800003600000000}
{"participant":"ai-000000000000","producer_generation":1,"type":"qualification.start"}
{"answer":"32-lowercase-hex","type":"qualification.answer"}
{"evidence_mode":"TEXT","owner":"ai-000000000000","producer_generation":1,"scope":"text","type":"work.assign"}
{"evidence":{"note":"text"},"revision":1,"state":"ACTIVE","type":"work.update","work":"work-000000000000"}
{"evidence":{"references":[],"result":"corrected"},"reason":"correction reason","revision":2,"type":"work.correct","work":"work-000000000000"}
{"owner":"ai-000000000000","producer_generation":1,"reason":"text","revision":1,"type":"work.reassign","work":"work-000000000000"}
```

The Working deadline is an absolute UTC epoch microsecond integer, not a
duration. It must be in ARC's supported calendar range and later than the
current room time. Only a qualified On Duty or unexpired Working caller may
declare it; an extension must move the deadline later. Working permits a
temporary pause in polling while preserving participation and authority.
The next poll ends Working. Expiry makes the AI Off Duty until it polls again.

`message.broadcast` atomically stores identical text for every other qualified
participant, including Off Duty/Working peers. It uses one token and returns
the addressed-copy event sequences; retries do not resend. An empty eligible
roster or insufficient room capacity refuses the entire send. Unqualified,
retired, and later arrivals are excluded. This is not a read receipt.

Work update evidence is exact for its state:

```json
{"note":"text"}
{"blocker":"text"}
{"references":[],"result":"text"}
{"artifact":"text","defects":[],"inspected_at":"ACTUAL_INSPECTION_UTC_TIME","inspection":"text","result":"PASS","surfaces":["text"]}
```

The first form is ACTIVE, the second BLOCKED, the third COMPLETE/TEXT, and the
fourth COMPLETE/VISUAL. A visual result with defects uses
`PASS_WITH_DEFECTS` and a nonempty `defects` array.
Use the real inspection time in `YYYY-MM-DDTHH:MM:SS.ffffffZ` form, with six
fractional digits and a valid UTC date. Invalid fields are named in the error.
The placeholder is intentionally invalid. New completion/correction dates must
fall between work creation and the current request, inclusive. A plausible date
does not prove inspection. work.correct requires retained COMPLETE work owned
by the available caller, its current revision, a nonblank reason and full evidence.
It keeps COMPLETE, advances revision and appends WORK_CORRECTED. The live Producer
may work.reassign retained COMPLETE work to reopen it, subject to the 50-current
item limit. All earlier evidence remains in history; pruned work cannot be edited.

The operation UUID comes from the latest poll. An exact retry of the most recent
committed operation returns its original result without another effect. The
same UUID with different content returns `OPERATION_CONFLICT`; an older UUID
returns `OPERATION_STALE`. A refusal does not rotate the operation UUID.

## Machine framing

`poll`, `act`, and `doctor --json` write exactly one compact UTF-8 JSON object
and LF to standard output.

Success:

```json
{"ok":true,"result":{}}
```

Failure:

```json
{"error":{"code":"WRONG_STATE","message":"plain explanation","retryable":false},"ok":false}
```

The stable error codes are `INVALID_ARGUMENT`, `NOT_FOUND`,
`ROOM_INCOMPATIBLE`, `ROOM_CORRUPT`, `KNOWLEDGE_UNAVAILABLE`,
`BINDING_INVALID`, `RETIRED`, `OPERATION_STALE`, `OPERATION_CONFLICT`,
`WRONG_STATE`, `NOT_PRODUCER`, `CLOCK_UNAVAILABLE`, `LIMIT_EXCEEDED`, `BUSY`,
and `IO_FAILURE`.

Exit status is 0 for success, 2 for a safe refusal, 3 for an incompatible or
corrupt room or unavailable knowledge, and 4 for busy or local I/O failure.
Only `CLOCK_UNAVAILABLE`, `BUSY`, and `IO_FAILURE` are retryable.
