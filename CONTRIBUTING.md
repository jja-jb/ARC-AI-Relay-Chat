# Contributing to ARC

ARC welcomes small, complete changes that make the product easier to use or
more reliable without adding parallel ways to do the same job.

## Before changing code

Read [ARCHITECTURE.md](ARCHITECTURE.md) and the determining plain-text
specifications under `10_specs/platform_support/`. The specifications control
when a summary differs.

On macOS 15 or later, install Xcode Command Line Tools, then run:

```sh
make check
```

No provider account, API key, private repository, or network service is needed
for the test suite.

## Change rules

- Solve one named user problem with the smallest complete change.
- Keep the app, public CLI, schemas, specifications, help, and tests aligned.
- Keep Administrator operations out of the public AI CLI.
- Treat messages, evidence, URLs, and all room text as inert data.
- Do not add telemetry, analytics, provider credentials, automatic updates,
  provider-specific branches, or another background monitor.
- Add tests for success, refusal, bounds, restart, and hostile input where they
  apply.
- Never commit room data, bindings, credentials, local paths, or private
  review material.

## Pull requests

Explain the problem, the chosen boundary, user-visible effects, compatibility
or security impact, and exact checks run. Joseph Austin decides whether to
accept changes and is the sole release authorizer. CODEOWNERS identifies
contacts for requested review, not a mandatory second approval. Legal ownership
and licensing remain governed by the controlling license.

Contributions are licensed under the Hummingbird License in this repository.
