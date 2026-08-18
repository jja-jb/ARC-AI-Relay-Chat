# Develop ARC

## Requirements

- macOS 15 or later
- Xcode Command Line Tools
- Git for source-control checks

The package has no remote dependency and the build needs no network access.

## One check

```sh
make check
```

This compiles and tests Swift and C, checks the knowledge round trip, validates
the source and documentation contract, and checks the development app.

Useful focused commands:

```sh
swift test
make knowledge-test
make app-development-check
make app-release-check
```

Generated files stay under `.build/`, `build/`, or `output/` and are never
source inputs.

## Design rules

- Keep one ARCCore implementation for app and command.
- Keep one canonical JSON file as the room authority.
- Keep Administrator operations out of the public AI command.
- Require explicit room, participant, binding, role, generation, and revision
  facts at their relevant operation boundary.
- Treat every name, message, scope, URL, and evidence value as inert data.
- Keep the first screen understandable to a reader age 14 or older.
- Add no provider branch, background agent, second storage model, hidden helper,
  remote package, telemetry, credential store, or network path.
- Align specifications, help, tests, and user-visible wording in the same change.

## Tests

Tests use isolated temporary ARC roots and synthetic room records. Never use a
real Application Support room as a fixture. Cover success, exact boundary,
first refusal, stale retry, lock contention, interrupted publication, hostile
text, restart, and user-visible next action.

Release changes also follow [docs/RELEASING.md](docs/RELEASING.md) and require
external DVT of the exact prepared candidate.
