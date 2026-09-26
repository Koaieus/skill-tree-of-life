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
board mechanics — the `gh` flag traps, the `add`-before-`status` order, the
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
   Handles (`@name`) let the Opus session write sibling references before the
   numbers exist; resolving them is mechanical, rewriting is not.
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
   once; prose would be context it pays for.
6. **Haiku.** The work is tool calls against a fixed recipe. If a manifest
   shape turns out to need judgement, the fix is a clearer manifest field, not
   a bigger model.

## What the agent file must not contain

Any issue number from the corpus, the cost argument, or why a trap exists
beyond the one clause that makes it recognisable.

## Corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-09-26 | owner | on the proposal to hand the swarmify tail to a Haiku agent: "Clerk does the mechanical stuff that's just tool calls. New agent file too perhaps? and a charter? supplying it with whatever any swarmifying agent would (use this and that tool this that caveat) so they don't even need to output *that*." | all |
| 2026-09-26 | tail measurement (59 swarmify sessions; `.claude/skills/swarmify/corpus/2026-09-26-tail-measurement.md`) | numbers in the cost argument above. Failures inside tails, by kind: `gh` `--json` field names that had moved (`blockedByIssues`); relations set on a child not yet created, or a milestone typo, exiting 1; hygiene violations fixed by hand; ~15 identical re-runs after a failure. No backtick-mangled `--body` — `--body-file` already holds | 3 |
| 2026-09-26 | first dry run (read-only manifest: two drift checks + hygiene) | 7 calls, ~35k Haiku tokens, report in the specified shape; `no stamp` on a `/warp`-made issue correctly reported as FAILED | 5, 6 |
