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
| `ROOM_INCOMPATIBLE` | room is not the ARC 1.0 format |
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

Act accepts at most 131,072 bytes. ARC rejects invalid UTF-8, duplicate or
unknown keys, floats, exponent notation, leading-zero or out-of-range integers,
more than 32 levels of nesting, and an object or array with more than 4,096
members. Text is trimmed, NFC-normalized, bounded, and free of disallowed
control characters before use.

An accepted act returns `event_sequences`, `room_revision`, nullable affected
`participant` and `work` views, and `next_operation`. The exact retry of the
latest committed operation receives the same result. Any refused action leaves
the current operation UUID available.

Poll result and nested view fields are normatively defined in specification
007. The durable JSON file is separately defined in specification 011; it is
not a machine response and must not be used as an AI command surface.
