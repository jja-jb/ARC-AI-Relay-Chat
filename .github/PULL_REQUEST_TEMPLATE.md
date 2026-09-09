## Purpose

Describe the user problem and the smallest complete change that solves it.

## Product agreement

- [ ] The main app, optional activity window, CLI, schema, specifications, help, and
      public documentation still agree.
- [ ] The change adds no parallel workflow for an existing ARC action.
- [ ] Room text stays inert, and no timer or record is described as proof that
      a provider displayed or acted on a message.
- [ ] Compatibility and security effects are explained.

## Verification

List the exact commands and results, including failures and unrun checks.
Use `make check` and relevant package verification from `docs/RELEASING.md`.
Joseph Austin alone authorizes releases; independent DVT is optional evidence
when he requests it, not a second approval requirement.

## Hygiene

- [ ] Tests cover success, refusal, and relevant hostile input.
- [ ] No credential, binding, room data, local path, generated build output, or
      private review material is included.
- [ ] Public copy is factual, modest, and supported by the current candidate.
- [ ] I read `CONTRIBUTING.md`, `SECURITY.md`, and `CODE_OF_CONDUCT.md`.
