# Terse 2.1 in ARC 2.5.1

`001-terse-language-specification.txt` is the complete governing ARC specification
013, now **Terse 2.1, wire integer 3**. Its thirty classic words remain; sections
20–26 add structured packets, context/reference/delta, batching, local validation,
tracked declarations, fixed reporting profiles and comparative cost measurement.
The canonical filename is unchanged. No external file or download is needed.

Current source SHA-256: `afc0e5bb6cbe47401aa757c93af5d9141a9831622e17459d4ededdbc7ca31027`.
ARC 2.5.1 changes only the production/version heading, not the language grammar.
The original 2.5.0 Terse bytes remain in its unchanged tag with SHA-256
`378aba7b229cf1985b77cdb934662c346929aae4ba9da249a3317f4a2ca4d723`.
ARC 2.5 introduces Terse 2.1 / wire 3 to remove ambiguous numeric failure
labels, clarify silent-observer instructions and document self-addressed packets.
Section 13.9 requires a new wire identifier for changed normative meaning.
Historical wire-2 packets keep their grammar and display; new sends require
current declarations and a complete verified reread. The original Terse 2.0
source remains in the unchanged ARC v2.4.0 tag, SHA-256
`fdd93c6be7892ac2269472c7213b34a20f013b5b93afb95688ae90106d4552b2`.

The prior Terse 1.0 source is preserved in the unchanged ARC v2.2.0 Git tag,
SHA-256 `cce23937fc0dfb838009f486d9ed99bd20ba7666750e7ac8b6d219e04979b424`.
Earlier development drafts predate formal versioning. Draft 7 remains in ARC's
v2.0.0 tag; the original operator-supplied draft 6 is in the v1.1.0 tag (SHA-256
`de045eb98ffd9908f44a647d1b894c94013e054d1e7a7d96d42d4fb4aab2eab9`).
Do not rewrite old release tags or describe the new grammar as wire 1.

Builds install the entire tracked text with a generated SHA-256 sidecar under
`current/languages/terse/`, covered by the signed atomic installation manifest.
It remains separate from the fixed Profile 1 knowledge container. `spec read 013`
returns the complete verified file. Read section 19 first, then all sections and
appendices. Changed bytes or lost context require a full reread. Declarations
record a participant's claim, never proof of reading or retained understanding.

The [integration guide](../../docs/TERSE_2_GUIDE.md) describes all seven features,
exact commands and the cost-import schema. The [test reconciliation](../../docs/ARC_2_3_TEST_REVIEW.md)
records the prior live test's layout-reference finding and the next testing plan.
The [specification index](../../10_specs/platform_support/001-shared-how-to-read-these-specs.txt)
lists all fourteen governing contracts.

Use Terse whenever it conveys the intended concept accurately. Otherwise the
sender, not the Producer, chooses tagged English or German for that concept.
Never repeat the same concept in both languages or add prose to a sufficient
Terse claim. The operator's selected language applies to human replies only.

ARC validates the structured path and offers local syntax tools; it does not
syntax-filter ordinary messages, verify claim truth, prove comprehension or
enforce semantic language choice. No Terse text executes a tool, grants access
or completes work. A matched cost report must include onboarding, accumulated
context, host/tool calls, repairs and failed attempts. Imported actual figures
are distinct from estimates; token savings remain unproven until measured.
