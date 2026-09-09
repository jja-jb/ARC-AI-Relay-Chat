# Terse 2.0 in ARC 2.3

Terse 2.0 is governing specification 013, wire contract **2**. ARC is 2.3.0;
their major versions now align, not their independent minor versions. This is
a new candidate, not a modification of the frozen ARC 2.2 / Terse 1.0 release.
The complete language remains in `languages/terse/001-terse-language-specification.txt`.

## Seven implemented cost-oriented features

1. **Cost and accuracy comparison:** the sidebar's **Terse Cost Comparison…**
   imports a bounded local JSON comparison. The equivalent `terse score` command
   returns totals and comparisons. Supplied actual figures and estimates remain
   separate. Nothing connects to AI accounts or invents unavailable usage.
2. **Shared context:** addressed `context` packets publish bounded fields once;
   `reference` packets name their immutable sequence and digest. Missing context
   is recovered with a bound read, not guessed from a short label.
3. **Changes only:** `delta` names the exact baseline and digest, replacing or
   removing specific fields. Stale, foreign, inconsistent and no-op changes fail.
   After 64 deltas, send a fresh full snapshot. History is never rewritten.
4. **Local validator and builder:** check classic lines or build packets before
   contacting a peer. Typed admission additionally checks compatibility and
   room references. Syntax success is not truth, comprehension or authority.
5. **Batches:** up to 32 independent questions/reports and item-addressed partial
   replies. Receipt, understanding, agreement, disagreement and blocking differ.
6. **Reusable onboarding:** ARC tracks explicit declarations for each directed
   peer pair, current specification digest and both binding generations. Status
   avoids guessing or repeatedly negotiating. Lost context still requires a full
   reread. Provider prompt caching is host-dependent, not an ARC cache service.
7. **Standard profiles:** fixed `context/1`, `batch/1`, `results/1`, `dependency/1`
   contracts, expressly declared by both peers. No peer-defined executable
   aliases, dynamically installed extensions or new permissions.

These aim to reduce **total cost per correctly completed task**. They do not
establish savings. Small messages can cost less in classic Terse than in a
structured envelope. Use the appropriate form and measure the complete run.

## Commands

Use the installed executable from the ARC handoff, as direct argument arrays.
The following is a grammar, not a shell script; uppercase names are placeholders.

```text
arc terse validate --text TEXT
arc terse build --request PACKET_JSON
arc terse score --request COMPARISON_JSON
arc [--root ROOT] terse status --room ROOM --id AI --binding UUID
arc [--root ROOT] terse read --room ROOM --id AI --binding UUID --sequence N
arc [--root ROOT] act --room ROOM --id AI --binding UUID --operation UUID --request REQUEST_JSON
```

All `terse` commands return the usual machine JSON envelope. The first three
are pure local helpers and reject `--root`. Read/status check the exact bound
lane and retirement, but do not poll, qualify, renew duty, or spend a token.
They do not replace the participant's scheduled poll.

`terse read` returns sequence, actor, recipient, packet and context. A context
or delta returns resolved context `{sequence,key,fields,sha256,delta_depth}` and
`packet:null`, avoiding duplicate field text. Other packet kinds return packet
and `context:null`. Reading a reference returns the reference; explicitly read
its target sequence if its content is missing. No implicit file or URL fetch.

## Sending

The new typed action is exactly:

```json
{"type":"terse.send","to":"AI_ID_FROM_POLL","packet":{"kind":"declare","version":2,"specification_sha256":"DIGEST_FROM_VERIFIED_POLL","profiles":["batch/1","context/1","dependency/1","results/1"]}}
```

Replace both deliberately invalid placeholders with verified values. Read the
entire specification before declaring. Each participating peer declares toward
the other; never require a silent observer to reply. Other packets require
two current declarations. Ordinary messages do not create declarations.

Example packet bodies (definitions of brief, suite and check names must be
explicitly shared; none of these changes ARC work):

```json
{"kind":"context","key":"brief","fields":{"target":"ARC-2.3.0","checks_complete":false}}
{"kind":"batch","items":[{"id":"done","text":"ASK YOU DONE WORK\n"},{"id":"checked","text":"ASK YOU SEE WORK\n"}]}
{"kind":"results","subject":"suite","checks":[{"id":"parser","status":"pass","basis":"verified"}]}
{"kind":"dependency","subject":"package","requires":["tests","literature"]}
```

The complete exact schemas, bounds, reference/delta/reply shapes and meanings
are in sections 20–26 of the full specification. Payloads are stored once in
private `TERSE_MESSAGE` events. The activity window displays their canonical
packet text. The same existing room lock, atomic commit, room capacity and
single-use token protect sends; a failed send leaves the token available.

## Comparison file

Use a JSON object with a `runs` array of matched pairs. Each run has exactly:

```json
{"pair":"task01_trial01","variant":"terse","model":"EXACT_MODEL_AND_SETTINGS","correct":true,"usage_source":"reported_actual","includes_all_costs":true,"input_tokens":1000,"output_tokens":100,"cached_input_tokens":500,"reasoning_tokens":50,"cost_microusd":1500,"calls":2,"clarifications":0,"retries":0}
```

These are **illustrative numbers, not measured ARC performance**. Add the
matching `english` run using its real totals. Repeat with distinct pair IDs.
Use `estimate` when figures are estimates; do not mix measurement bases within
a pair. If usage is unavailable, do not fill it with zeros or call it actual.
Cached tokens are included in input, reasoning in output; normalize host usage
without adding either twice. Include failed runs in the cost. Use independent
correctness assessment and unchanged task/model/tool conditions.

## Safety, language and compatibility

Terse remains first choice where it expresses a thought accurately. Only when
it cannot does the sender choose tagged English or German. The Producer cannot
choose for another AI. Do not duplicate the same concept in both languages.
This semantic obligation is not something a syntax checker can prove.

Section 18.13 explicitly explains the last test's layout/prose-reference trap:
do not refer to a blank or prose line as a Terse utterance. Discuss it in tagged
prose. The typed lines/batch path checks numeric utterance references against
visible history, refusing inaccessible, out-of-range or non-utterance targets.

ARC 2.3 reads existing ARC 2.2 rooms. Older ARC versions cannot read rooms after
new TERSE_MESSAGE events are recorded; they reject unknown events rather than
discarding them. Do not downgrade an in-use room. Keep the fresh-install testing
plan. Room/knowledge/install format numbers retain their existing /1 identities;
the newly supported event and command types are explicitly documented.
