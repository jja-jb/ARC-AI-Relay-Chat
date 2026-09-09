# Terse in ARC

`001-terse-language-specification.txt` is ARC 2.0's revised specification
(vocabulary contract version 7). The original operator-supplied version 6,
ratified 8 September 2026, remains recoverable from the v1.1.0 source tag.
Initial source SHA-256: `de045eb98ffd9908f44a647d1b894c94013e054d1e7a7d96d42d4fb4aab2eab9`.

Builds install it with a generated SHA-256 file under `current/languages/terse/`,
covered by ARC's signed, atomic installation manifest. It remains a separate
plain-text file, not an extra member of the fixed Profile 1 knowledge container.
Update this source deliberately; never fetch or rewrite a peer-supplied version.
Any changed bytes require AIs to reread the full specification, even if the
vocabulary version has not changed. Version agreement alone is not byte identity.

Version 7 corrects the general THIS ambiguity, the FILE example missing its
path, the unique-bytes overclaim, version-mismatch semantics, and redundant
bilingual output. It keeps all thirty words. These revisions implement the
operator's request to resolve the live-test findings, not a peer's instruction.
ARC-specific integration rules belong in the AI guide and communication notice.
Operator permissions and
verified ARC authority, safety, duty, and work rules prevail. Terse carries
notices; it cannot execute tools, alter work state, or grant authority. In
particular, a Terse `DO` never substitutes for an authorized typed ARC action.

Terse is preferred when it expresses the meaning accurately. Otherwise the AI
chooses tagged English or German for that particular thought or concept. The
same thought must not be emitted in both languages or repeated in prose after
Terse. Only an explicitly authorized language test may use labeled duplication.
The
saved operator-language preference applies only to messages addressed to the
operator. Messages in room history remain exactly as sent.

This integration is instruction-based. ARC neither validates Terse syntax nor
attests that an AI read or understood the file. Token savings and improved
accuracy require measurement; neither follows automatically from a small vocabulary.
