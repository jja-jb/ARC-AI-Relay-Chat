# ARC 2.5.1 production checklist

Joseph Austin is the sole release authorizer. This is a verification checklist,
not a request for another reviewer or independent approval.
See [the release procedure](docs/RELEASING.md) and
[production decision](docs/ARC_2_5_1_PRODUCTION_RELEASE.md).
Unchecked items describe work to verify, not claimed results.

## Source and content

- [ ] App version 2.5.1, build 251, command, specs, manuals and release agree.
- [ ] Source includes the Swift 6.1.2 test-compatibility correction.
- [ ] Terse remains 2.1 / wire 3, with production status and a verified new digest.
- [ ] Tests run; actual failures and accepted exceptions are recorded.
- [ ] Traceability, support links, legal text and source inventory are checked.
- [ ] Graphics are accounted for; the radio is labeled as a concept illustration.
- [ ] Both pages of the current literature PDF are visually checked.
- [ ] Clean annotated tag, main and exact source archive match.

## Package and publication

- [ ] App and command are arm64-only; identity is org.jonnybass.arc.
- [ ] Installed specs, knowledge, Terse and legal files match the tagged source.
- [ ] Signatures, notarization, staples and Gatekeeper verification succeed.
- [ ] DMG contains ARC.app and the Applications link.
- [ ] Acceptance and metadata describe actual evidence without invented PASS rows.
- [ ] SHA256SUMS covers every other public asset.
- [ ] Issues, Discussions, private reporting and support links are available.
- [ ] Main blocks force pushes and deletion; no second reviewer is required.
- [ ] Joseph Austin has authorized production publication.
- [ ] GitHub Release is production/Latest and downloaded bytes match local assets.
- [ ] Earlier published tags and downloads remain unchanged.
