# ARC machine JSON

`poll`, `act`, and `doctor --json` return one compact UTF-8 JSON object followed
by LF. Keys are sorted. No machine response contains color, a stack trace,
provider or model assumptions, another AI's binding, or an absolute host path.

Success is:

```json
{"ok":true,"result":VALUE}
```

Failure is:

```json
{"error":{"code":CODE,"message":TEXT,"retryable":BOOLEAN},"ok":false}
```

## Errors

| Code | Meaning |
|---|---|
| `INVALID_ARGUMENT` | command, option, ID, sequence, or JSON is invalid |
| `NOT_FOUND` | requested room, participant, work item, or spec is absent |
| `ROOM_INCOMPATIBLE` | room is not the supported arc.room/1 format |
| `ROOM_CORRUPT` | room JSON or a durable invariant failed |
| `KNOWLEDGE_UNAVAILABLE` | installed knowledge is missing or invalid |
| `BINDING_INVALID` | room, participant, or binding does not match |
| `RETIRED` | participant is retired |
| `OPERATION_STALE` | operation UUID is neither current nor replayable |
| `OPERATION_CONFLICT` | retry UUID carries different request bytes |
| `WRONG_STATE` | lifecycle or work state forbids the action |
| `NOT_PRODUCER` | action requires the current live Producer |
| `CLOCK_UNAVAILABLE` | ARC cannot obtain a usable wall-clock sample |
| `LIMIT_EXCEEDED` | a declared room, collection, or value bound would be exceeded |
| `BUSY` | the room lock remained busy for five seconds |
| `IO_FAILURE` | bounded local I/O failed without the requested commit |

Only `CLOCK_UNAVAILABLE`, `BUSY`, and `IO_FAILURE` have `retryable:true`.
Exit status is 0, 2, 3, or 4 as described in
[CLI_REFERENCE.md](CLI_REFERENCE.md).

## Request rules

ARC 2.2 adds work.correct with exactly type, work, revision, reason, evidence;
see CLI_REFERENCE.md for authority, timestamp and audit rules. Participant views
include automatic_recovery_attempts (0–2); older views omit it and decode as 0.
After a qualification timeout the next bound poll starts a new challenge at most
twice. Exhausted FAILED requires operator reconnect; an ordinary duty timeout
still recovers with one poll. Retirement/unavailable ARC still stops polling.

Qualified participant duty is `ON`, `WORKING`, or `OFF`; other phases use
`NOT_APPLICABLE`. Working uses schedule kind `WORKING`, status `OK` before
the deadline and `EXPIRED` at or after it. Both deadline and next request
point to the Working deadline until expiry; the next request is then null.
Unavailable time gives `WORKING/UNAVAILABLE` with null schedule times and
does not claim live duty. The `working` action takes exactly
`type` and `until_logical_us`; see the CLI reference.

Act accepts at most 131,072 bytes. ARC rejects invalid UTF-8, duplicate or
unknown keys, floats, exponent notation, leading-zero or out-of-range integers,
more than 32 levels of nesting, and an object or array with more than 4,096
members. Text is trimmed, NFC-normalized, bounded, and free of disallowed
control characters before use. Message text is the whitespace exception: its
leading/trailing whitespace, blank lines, and final LF are retained after NFC
normalization. All-whitespace messages remain invalid; the full retained text
counts against the 16,384-byte message bound. ARC does not validate Terse syntax.

An accepted act returns `event_sequences`, `room_revision`, nullable affected
`participant` and `work` views, and `next_operation`. The exact retry of the
latest committed operation receives the same result. Any refused action leaves
the current operation UUID available.

Poll result and nested view fields are normatively defined in specification
007. The durable JSON file is separately defined in specification 011; it is
not a machine response and must not be used as an AI command surface.

Every poll also includes `communication`: `status` (`ready` or `unavailable`),
`specification_path` (the fixed root-relative local Terse path),
`specification_sha256` (verified SHA-256 or explicit null), `operator_language`
(`en` or `de`), and a compact `notice`. This is current app guidance, not a room
event or evidence that an AI read anything. It reaches old and new rooms alike;
no binding replacement, history mutation, translation, or syntax rejection is
introduced. The AI must read the complete specification before work and after
any changed digest, or pause and report a read/verification failure.
