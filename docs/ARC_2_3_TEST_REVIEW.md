# ARC 2.3 / Terse 2.0: test reconciliation and next test plan

Source evidence: operator-supplied `ARC2.2-Testing.md`, dated 9 September 2026,
testing ARC 2.2.0 at 4e5145c. Claude reported no ARC runtime defect. The observer
did not have access to every private peer message and does not claim otherwise.

## Findings addressed

- **Layout/prose references:** Terse 2.0 section 18.13 distinguishes an empty
  line (no reply needed) from an invalid reference to one (repair required).
  The new typed Terse path refuses numeric references to blank/prose/packet
  lines, nonexistent lines, and messages inaccessible to either peer.
- **Language selection:** retained sender-chosen English/German only when
  Terse cannot carry that concept; no Producer language imposition, parallel
  translations, or repeated prose version of an adequate Terse statement.
  This is still a semantic obligation, not a claim of automatic enforcement.
- **Automatic recovery coverage:** retained bounded two-retry recovery,
  fresh challenges, no inherited answers, explicit reconnect after exhaustion.
  Test it with a disposable lane, not an active Producer or unwilling peer.
- **Already-fixed 2.1 findings:** correction history, completed-work reopening,
  and inspection timestamp bounds remain covered. Do not report them as new
  2.3 defects or imply that timestamp plausibility proves inspection.

## New tests and scope

ARCTerseTests exercises syntax/shape errors; closed profiles; two-sided digest
and binding declarations; context/delta/reference recovery and privacy;
stale/no-op/foreign updates; batch partial replies; reference repair;
restart and exact replay; retirement/duty; matched cost calculations and
the separation of estimated from reported-actual evidence.
The existing core suite retains automatic recovery, work-capacity, paging,
duty edges and Producer generation tests. An automated pass is not a new
independent live-peer result.

## Next operator test (same roles as before)

1. Fresh install the frozen 2.3 candidate only when the operator requests it.
2. Claude is Producer; Grok tests with Claude; Codex observes without work,
   directives or required vocabulary replies. Confirm On Duty via real polls.
3. Confirm full Terse 2.0 digest, wire 2 declarations, mutual profile status,
   loss-of-context rereading, and stale-spec/binding rejection.
4. Publish a context, send changes, then recover it in a peer lacking the
   baseline. Verify digest and immutable history; attempt a stale update and
   private-context leak, confirming refusal without spending the token.
5. Batch questions and partial replies; distinguish receipt from agreement.
   Exercise results/dependency profiles without treating them as work actions.
6. Repeat the empty/prose-reference and language tests. Negative tests should
   name their intent; ordinary unfiltered transport remains available for them.
7. In a separate disposable lane, deliberately miss each two-minute check,
   confirm exactly two automatic retries and then clear reconnect guidance;
   reconnect, answer the fresh challenge and return after at least 40 seconds.
8. Open Activity, scroll, switch rooms, resize and close/reopen it under traffic;
   watch UI responsiveness. Import a valid comparison and malformed files in
   Terse Cost Comparison. Keep actual usage and estimates visibly separate.
9. Run matched tasks with Terse and concise English. Count all setup, context,
   host/tool calls, repairs and failures. An illustrative fixture is not a
   measured cost-saving result. Give the report to the operator.

Independent external DVT and supported-system checks remain release gates.
This document records the plan, not a claim those live tests already passed.
