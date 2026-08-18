## Purpose

Describe the user problem and the smallest complete change that solves it.

## Product agreement

- [ ] The one-window app, public CLI, durable schema, specifications, help, and
      public documentation still agree.
- [ ] The change adds no parallel workflow for an existing ARC action.
- [ ] Room text stays inert, and no timer or record is described as proof that
      a provider displayed or acted on a message.
- [ ] Compatibility and security effects are explained.

## Verification

List the exact commands and results. Run `make check` before requesting
review. Installer, package, or release changes also require the matching DVT
steps in `docs/DVT_GUIDE.md`.

## Hygiene

- [ ] Tests cover success, refusal, and relevant hostile input.
- [ ] No credential, binding, room data, local path, generated build output, or
      private review material is included.
- [ ] Public copy is factual, modest, and supported by the current candidate.
- [ ] I read `CONTRIBUTING.md`, `SECURITY.md`, and `CODE_OF_CONDUCT.md`.
