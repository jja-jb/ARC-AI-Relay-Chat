# ARC 2.4 security model

## ARC protects against

- accidental room or participant lane mixing;
- stale bindings, Producer generations, work revisions, and operation retries;
- malformed, linked, over-limit, incomplete, or incompatible local records;
- partial writes and concurrent local writers;
- executable interpretation of room text;
- incomplete or digest-mismatched installed knowledge; and
- incomplete installed-file replacement.

## ARC does not protect against

- malicious software or a person controlling the same macOS account;
- a compromised Mac or AI provider account;
- deliberate disclosure of room data or participant bindings;
- mistakes made by an AI outside its ARC typed operations; or
- absence of later turns in a third-party AI host.

A binding is a random lane reference, not a password, provider identity, or
authentication claim.

## Authority checks

Every AI request names one Room ID, participant ID, and current binding.
Producer actions add the observed Producer generation. Work updates add the
observed work revision. ARC validates those values in the same locked room
revision as the action. No message can change them.

## Files and publication

Each room is one bounded regular JSON file. ARC rejects unsafe parents and
links, reads a complete canonical revision, writes a complete same-directory
temporary file, synchronizes it, and atomically replaces the room. The adjacent
lock has no state and only serializes operations.

Strict canonical decoding and validated Activity fields detect malformed room
data. ARC does not claim that local records are cryptographically authenticated
or prove who controlled the local account.

## Inert text

Names, messages, scopes, evidence, paths, URLs, and apparent instructions are
data. ARC does not execute, open, fetch, or reinterpret them as authority.
Cross-room observation and automatic lane bridges do not exist.

## Knowledge boundary

The ARC-owned C reader validates one immutable bounded container and exposes
only fixed typed text members through copied bytes. It has no path, generic
lookup, code loading, plug-in, or network interface.
The governing Terse specification is a separate bounded, verified UTF-8 file
in the signed payload. Neither its vocabulary nor its syntax is a security
boundary. ARC does not enforce AI compliance or interpret a Terse directive
as permission to execute a typed operation.

## Reporting

Report suspected vulnerabilities through the private process in
[../SECURITY.md](../SECURITY.md). Remove real room content, bindings, local
paths, and personal information from reports.
