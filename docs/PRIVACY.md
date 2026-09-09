# ARC privacy

ARC 2.5 is local software. It opens no network connection and has no telemetry,
analytics, advertising identifier, provider login, credential store, cloud
sync, embedded browser, automatic upload, download, or update check.

## What ARC stores

Below `~/Library/Application Support/ARC/`, ARC stores:

- one canonical JSON file for each retained room;
- a zero-byte adjacent lock for local serialization;
- the installed native `arc` command;
- the full Terse v2.1 specification and digest;
- the app-wide operator-language preference, when explicitly saved;
- the current knowledge container, specifications, legal text, and install
  receipt.

A room contains its name and ID, participant names and lane bindings, Producer,
work, complete room history, retry facts, and local timestamps. ARC does not
store provider credentials or the surrounding provider-chat transcript.

## No ARC encryption

ARC relies on the current macOS account and device protections. It does not add
room encryption. Do not put API keys, passwords, or unnecessary personal or
private information in names, messages, scopes, or evidence.

## Required-reason APIs

The app privacy manifest declares no collected data and no tracking. It declares
file-metadata access for ARC-owned files (`C617.1`) and system elapsed-time access
for local timers (`35F9.1`). Neither value is sent off-device.

## Diagnostics and removal

Normal diagnostics omit message, work, evidence, binding, operation, and full
path content. Nothing is sent automatically.

Permanently deleting a room affects only that room and its history. Retiring an
AI does not
erase Activity. To remove all local ARC data, quit ARC and move its Application
Support folder to Trash after reviewing retained rooms.

See [SECURITY_MODEL.md](SECURITY_MODEL.md) for the trust boundary.
