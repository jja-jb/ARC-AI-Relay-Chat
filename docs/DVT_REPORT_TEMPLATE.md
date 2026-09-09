ARC 1.0 EXTERNAL DVT REPORT
schema: arc.dvt/1
version: 2.3.0
tag: v2.3.0
revision: <40 lowercase hexadecimal characters>
candidate_manifest_sha256: <64 lowercase hexadecimal characters>
tester: <name and organization independent of implementation>
independence: <plain statement of independence from ARC implementation>
started_at: <UTC time with fractional seconds; example 2026-08-17T19:00:00.000Z>
finished_at: <UTC time with fractional seconds; example 2026-08-17T20:00:00.000Z>
machines: arm64=<Mac model>
systems: arm64=<macOS version and build>
toolchains: arm64=<Xcode and Swift versions>
prepared_hashes: dmg=<SHA-256> | source=<SHA-256> | literature=<SHA-256> | manifest=<SHA-256>
deviations: No deviations.
decision: PASS
checks:
test: DVT-001-SOURCE | PASS | <evidence>
test: DVT-002-NATIVE-BUILD | PASS | <evidence>
test: DVT-003-INSTALL | PASS | <evidence>
test: DVT-004-FIRST-ROOM | PASS | <evidence>
test: DVT-005-TWO-AI-ACTIVE | PASS | <evidence>
test: DVT-006-QUALIFICATION-FAILURE | PASS | <evidence>
test: DVT-007-PRODUCER-CHANGE | PASS | <evidence>
test: DVT-008-REPLACE-AND-RETIRE | PASS | <evidence>
test: DVT-009-MESSAGES-AND-WORK | PASS | <evidence>
test: DVT-010-POLLING-RECOVERY | PASS | <evidence>
test: DVT-011-ROOM-INTEGRITY | PASS | <evidence>
test: DVT-012-PRIVACY-AND-OFFLINE | PASS | <evidence>
test: DVT-013-ACCESSIBILITY | PASS | <evidence>
test: DVT-014-AGE-14-USABILITY | PASS | <evidence>
test: DVT-015-SIGNING-NOTARIZATION | PASS | <evidence>
end: arc.dvt/1
