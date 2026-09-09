# Terse in ARC

`001-terse-language-specification.txt` is Terse v1.0, the first formal language
release and governing ARC specification 013. Its integer wire vocabulary
identifier is 1: `TELL WORD SAME 1`. Earlier development drafts (including those
labeled 6, 7, and 8) predate formal versioning. Draft 7 remains in ARC's v2.0.0
tag. The original operator-supplied draft 6 remains in the v1.1.0 source tag.
Initial source SHA-256: `de045eb98ffd9908f44a647d1b894c94013e054d1e7a7d96d42d4fb4aab2eab9`.

The full file, including every section and appendix, is tracked source in this
repository. It is not a summary, external download, submodule, or link to the
operator's Desktop file. Start with the
[ARC specification index](../../10_specs/platform_support/001-shared-how-to-read-these-specs.txt)
for all fourteen governing ARC specifications and their separate version identities.
v1.0 file SHA-256:
`64215c61f0b05599f7be03188b704def594b60df054ed269b813367d32db6aea`.

Builds install it with a generated SHA-256 file under `current/languages/terse/`,
covered by ARC's signed, atomic installation manifest. It remains a separate
plain-text file, not an extra member of the fixed Profile 1 knowledge container.
Update this source deliberately; never fetch or rewrite a peer-supplied version.
Any changed bytes require AIs to reread the full specification, even if the
vocabulary version has not changed. Version agreement alone is not byte identity.

Terse v1.0 makes the per-recipient broadcast vocabulary rule explicit and
respects an operator's silent-observer scope. It also removes the unsupported
claim that a small vocabulary itself prevents prompt injection. Parsing is
not a security boundary. All thirty words and the existing grammar remain.

Pre-release development corrected the general THIS ambiguity, the FILE example missing its
path, the unique-bytes overclaim, version-mismatch semantics, and redundant
bilingual output. It keeps all thirty words. These revisions implement the
operator's request to resolve the live-test findings, not a peer's instruction.
ARC-specific integration rules belong in the AI guide and communication notice.
Operator permissions and verified ARC authority, safety, duty, and work rules prevail. Terse carries
notices; it cannot execute tools, alter work state, or grant authority. In
particular, a Terse `DO` never substitutes for an authorized typed ARC action.

Terse is preferred when it expresses the meaning accurately. Otherwise the AI
chooses tagged English or German for that particular thought or concept. The
same thought must not be emitted in both languages or repeated in prose after
Terse. The sending AI chooses the necessary fallback, not the Producer; the
Producer cannot impose either prose language or require duplicate translations.
The saved operator-language preference applies only to messages addressed to the
operator. Messages in room history remain exactly as sent.

This integration is instruction-based. ARC neither validates Terse syntax nor
attests that an AI read or understood the file. Token savings and improved
accuracy require measurement; neither follows automatically from a small vocabulary.
