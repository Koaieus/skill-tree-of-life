# Clerk — charter

The design behind `.claude/agents/clerk.md`. The agent file is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol.

## What the clerk is for

A `/swarmify` pass ends in a stretch of pure tool calls: post the spec, create
the children, wire parent and blocked-by relations, set status, labels and
milestone, check the drift stamp parses, run hygiene, verify. None of it is
thinking — every word posted and every decision recorded already exists — but
it runs in the Opus session at that session's *largest* context, and every
call re-sends all of it. The clerk takes that stretch: the Opus session writes
the spec files and a manifest, spawns one Haiku clerk, and reads back one line
per issue.

The second win is that the swarmify session no longer has to *carry* the
board mechanics — the `gh` flag traps, the
milestone rule — in its instructions or its output. The clerk holds them;
swarmify only states intent.

## The cost argument

Σ(context × turns) is the cost (`mise run agent-cost` measures it). The tail's
turns are cheap in thought and expensive in context: they sit at the end of a
session that has read the issue, the code, the fork discussion and the spec.
Moved to a fresh Haiku context carrying only the manifest, each turn costs a
small fraction, and the Opus session pays one spawn and one short report.
Measured (corpus below): the tail — everything after the spec is drafted —
is 58–79% of a swarmify session's Σ(context), starting at a median ~116k
context; clerk-shaped turns are ~41% of it, 646 turns over 56 sessions.
Re-priced at `agent-cost` weights they drop ~89% (35.7M → 4.0M
sonnet-token-units), ~24–27% of whole-session cost. That assumed a 5k Haiku
brief; the first dry run spent ~35k over 7 calls (system prompt and tools
included), so the real saving is somewhat lower — still most of it, since
Haiku is priced a fifth of Opus and never carries the pass's context.

## Laws

1. **The clerk never decides.** It executes a manifest. Anything the manifest
   does not say, or any call that fails, is skipped and reported; independent
   steps still run. Improvising a missing milestone or rewording a spec is the
   failure this agent exists to not have — a Haiku judgement call in the one
   place the owner's words are being published.
2. **The only file edit is handle substitution**, on a `.resolved` copy.
   Handles (`{name}`) let the Opus session write sibling references before the
   numbers exist; resolving them is mechanical, rewriting is not. The sigil was
   `@name` until a leftover `#@`-handle in #1383 pinged a stranger (owner,
   2026-10-08: *'"@"s were a really bad pick for handles, fixing that
   forever'*): a handle must be inert when it leaks, and the gh shim refuses
   both a bare `@name` and an unresolved `#{name}`. New issues are created
   with a stub body and filled once every number exists, so no forward
   handle is ever posted, even transiently.
   The manifest grammar is the clerk's whole interface, and it is
   **duplicated verbatim in swarmify's step 10** so the pass writes a manifest
   without opening the agent file — a change to the grammar block here is a
   change to that copy in the same commit. `parent:` is a key on *existing*
   issues as well as `new` ones: a pass that promotes a child into a hub under
   a different parent, or files a sibling where a child was, re-parents
   through the manifest, not by hand; `parent: -` detaches it. The clerk's
   reach is bounded by the board rules (law 4), not by caution about
   relations: a relation the clerk refuses is one the Opus session then sets
   by hand at full context, which is the cost the clerk exists to remove.
3. **Every exit code is checked; nothing is piped through `tail`; nothing is
   retried blind.** The
   issue-workflow traps (`--add-parent` swallowed by a pipe, `blockedBy` as an
   object, the raw dependencies API taking internal ids, backticks in `--body`, a
   remembered `--json` field name that has since moved)
   all fail *silently*; the clerk's instructions carry each one so the spawning
   session does not have to.
4. **Board rules are enforced by refusal, not repair.** No `Ready` without a
   milestone, no status on a hub, no close/reopen/retitle, no git. A manifest
   that asks for one gets a `SKIPPED` line.
5. **The report is the whole output.** One line per issue, then drift,
   `refresh` when the manifest lists it, hygiene, then `SKIPPED` / `FAILED`. The spawning session reads it
   once; prose would be context it pays for. A re-parent's line names the old
   parent and how many open children it has left — a datum, not a warning:
   `hygiene --fix` and `land` close a hub whose children are all closed, and
   whether emptying one was intended is the pass's call, which it can only
   make if the report says it happened.
6. **Haiku.** The work is tool calls against a fixed recipe. If a manifest
   shape turns out to need judgement, the fix is a clearer manifest field, not
   a bigger model.

7. **A spent GraphQL hour is not waited out.** The quota refills up to an hour
   later; a clerk that sleeps, polls `rate_limit` or backgrounds a wait loop
   spends its turns and still fails. On the hourly-quota error it stops
   issuing GraphQL calls, still runs the REST-backed steps, and reports the
   rest `FAILED` with the cause — the spawning session re-runs those later.
   Relations are REST-first (`gh-project blocked-by`), since a pass's
   dependency wiring is the part least worth losing. The rest stays on `gh
   issue …` (GraphQL, ~1 point a call): the 2026-10-01 exhaustion was board
   reads across sessions at ~600 points each — spent before the clerk's first
   failing call — not issue writes, and wholesale REST
   would put the internal-id trap (parent links take ids too) in Haiku's
   hands.

## Fold digest

| Date | Kind | Became |
|---|---|---|
| 2026-10-03 | friction | `parent:` / `parent: -` on existing issues (law 2); re-parent line reports the old parent's open-child count (law 5); grammar block mirrored in swarmify step 10 |

## What the agent file must not contain

Any issue number from the corpus, the cost argument, or why a trap exists
beyond the one clause that makes it recognisable.

## Corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-09-26 | owner | on the proposal to hand the swarmify tail to a Haiku agent: "Clerk does the mechanical stuff that's just tool calls. New agent file too perhaps? and a charter? supplying it with whatever any swarmifying agent would (use this and that tool this that caveat) so they don't even need to output *that*." | all |
| 2026-09-26 | tail measurement (59 swarmify sessions; `.claude/skills/swarmify/corpus/2026-09-26-tail-measurement.md`) | numbers in the cost argument above. Failures inside tails, by kind: `gh` `--json` field names that had moved (`blockedByIssues`); relations set on a child not yet created, or a milestone typo, exiting 1; hygiene violations fixed by hand; ~15 identical re-runs after a failure. No backtick-mangled `--body` — `--body-file` already holds | 3 |
| 2026-09-26 | first dry run (read-only manifest: two drift checks + hygiene) | 7 calls, ~35k Haiku tokens, report in the specified shape; `no stamp` on a `/warp`-made issue correctly reported as FAILED | 5, 6 |
| 2026-10-03 | #1311 → hub under #1255 (was a child of #1217) | the manifest had `parent:` only on `new` issues, so the pass re-parented by hand (REST `sub_issue` DELETE + `sub_issues` POST) at full context, then had to open the agent file to learn the manifest keys; `hygiene --fix` then closed the emptied #1217 with nothing having said it would | 2, 5 |
| 2026-10-03 | owner | on leaving `--remove-parent` out of the clerk: "if the clerk doesn't do it then a more costly agent must" | 2 |
| 2026-10-01 | reticle pass (#1284, six children) | creates, comments and body edits landed; then every `--add-blocked-by`, `milestone` and `issue view` died on "API rate limit already exceeded" — the hourly GraphQL quota, spent by `gh-project status <n>` reads at ~607 points each (now ~1). The clerk tried `sleep 60`, a `rate_limit` poll loop and backgrounded `gh-project` calls hung in the shim's backoff; the parent session finished by hand, links via REST `dependencies/blocked_by`. Owner: "The clerk charter updating to direct using REST first might be good nonetheless" | 7 |
