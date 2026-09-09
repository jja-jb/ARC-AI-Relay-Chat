# Security policy

## Report privately

Do not open a public issue for a suspected vulnerability.

Use GitHub Private Vulnerability Reporting from the repository's **Security**
tab and begin the title with `[ARC SECURITY]`. Include the ARC version, Mac
version and architecture, the smallest reproduction, expected result, and
actual result. Remove credentials, bindings, room content, local paths, and
unrelated personal information.

If the private form is unavailable, use GitHub's maintainer-contact route to
ask for a private channel without including vulnerability details.

ARC is provided without a response-time, remediation-time, or support promise.

## Security boundary

ARC protects a careful user from accidental lane mixing, malformed local data,
and incomplete writes. It validates room identity, participant binding,
authority, state, bounds, complete room history, and the installed knowledge
container before use.

ARC trusts software already controlling the same macOS account. A participant
binding separates ARC lanes; it is not provider authentication. ARC does not
log in to providers, store provider credentials, fetch room content, execute
room text, or claim that a provider displayed or acted on a message.

Reports may cover ARC.app, the core and command, room storage, the
knowledge reader, installers, privacy behavior, documentation that could cause
unsafe operation, and release artifacts.

The latest generally available ARC release is eligible for a correction when
the maintainers choose to provide one. ARC 2.5.0 is currently a prerelease
under acceptance testing. Prereleases, development snapshots and older releases
have no promised maintenance period.
