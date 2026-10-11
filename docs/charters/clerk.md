# Clerk — charter

The design behind `.claude/agents/clerk.md`. The agent file is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol.

## What the clerk is for

A spec ends in a stretch of pure tool calls (the [spec](spec.md) skill's
last step, run from a `/swarmify` pass or a headless lead): post the spec, create
the children, wire parent and blocked-by relations, set status, labels and
milestone, check the drift stamp parses, run hygiene, verify. None of it is
thinking — every word posted and every decision recorded already exists — but
it runs in the calling session at that session's *largest* context, and
every call re-sends all of it. The clerk takes that stretch: the caller writes
the spec files and a short prose work order, spawns one Haiku clerk, and
reads back one line per issue.

The second win is that the swarmify session no longer has to *carry* the
board mechanics — the `gh` flag traps, the
milestone rule — in its instructions or its output. The clerk holds them;
swarmify only states intent.

## The cost argument

Σ(context × turns) is the cost (`mise run agent-cost` measures it). The tail's
turns are cheap in thought and expensive in context: they sit at the end of a
session that has read the issue, the code, the fork discussion and the spec.
Moved to a fresh Haiku context carrying only the work order, each turn costs a
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

1. **The clerk never decides content.** Turning a sentence into the right
   calls is its job; choosing what the board should say is not. A wording, a
   missing milestone, a status the order does not state, a fix to a spec —
   skipped and reported; independent steps still run. A sentence with two
   readings that leave the board in different states is skipped and
   reported, not guessed. Improvising content is the failure this agent
   exists to not have — a Haiku judgement call in the one place the owner's
   words are being published. (Was "never decides" over a grammar; narrowed
   2026-10-11 with law 2.)
2. **The interface is a plain-prose work order.** One line or short
   paragraph per issue saying what should be true afterwards — "under
   #1130, body state.md, blocked by {state}, Ready". It replaced a keyed
   manifest grammar (owner, 2026-10-11: *"Maybe more free prose should be
   better and just explain in Clerk what the tools are so they don't trip up
   on syntax errors while bash golfing. I'm pretty sure they can understand
   'file blabla issue parented under #123 set blocked by #122' pretty
   well"*). The grammar had to be duplicated into swarmify so the pass would
   not open this file, and still it was opened in 25 of 54 sessions; each gap
   it had (re-parenting, clearing blockers) needed a new keyword, where a
   sentence needs nothing. The caller writes intent; the clerk holds the
   calls. Its reach is bounded by the board rules (law 4), not by caution
   about relations: a relation the clerk refuses is one the caller then sets
   by hand at full context, which is the cost the clerk exists to remove —
   so re-parenting (`--parent`, `--remove-parent`) and clearing blockers are
   in its reach.
   **The one kept convention is the handle.** `{name}` declares an issue not
   yet filed; `#{name}` inside any file the clerk posts — body *or* comment —
   is replaced by `#<number>` on a `.resolved` copy, the only file edit it
   makes. New issues are created with a stub body and filled once every
   number exists, so no forward handle is ever posted. The sigil was `@name`
   until a leftover `#@`-handle in #1383 pinged a stranger (owner,
   2026-10-08: *'"@"s were a really bad pick for handles, fixing that
   forever'*); the gh shim refuses both a bare `@name` and an unresolved
   `#{name}`. Before reporting, the clerk re-reads every body and comment it
   posted and confirms no `#{` survives.
3. **Every exit code is checked; nothing is piped through `tail`; nothing is
   retried blind.** The
   issue-workflow traps (`--add-parent` swallowed by a pipe, `blockedBy` as an
   object, the raw dependencies API taking internal ids, backticks in `--body`, a
   remembered `--json` field name that has since moved)
   all fail *silently*; the clerk's instructions carry each one so the spawning
   session does not have to.
4. **Board rules are enforced by refusal, not repair.** No `Ready` without a
   milestone, no status on a hub, no close/reopen/retitle, no git. An order
   that asks for one gets a `SKIPPED` line.
5. **The report is the whole output.** One line per issue, then drift,
   `refresh` when the order asks for it, hygiene, then `SKIPPED` / `FAILED`. The spawning session reads it
   once; prose would be context it pays for. A re-parent's line names the old
   parent and how many open children it has left — a datum, not a warning:
   `hygiene --fix` and `land` close a hub whose children are all closed, and
   whether emptying one was intended is the pass's call, which it can only
   make if the report says it happened.
6. **Haiku.** The work is tool calls against a fixed recipe. If an order
   turns out to need judgement, the fix is a clearer sentence in spec's
   example work order or a row in law 8's table, not a bigger model.

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

8. **The vocabulary is spelled out.** Statuses are the `gh-project` slugs
   `backlog | needs-design | ready | in-progress | in-review | done`,
   whatever case the order writes them in; a milestone is set through
   `gh-project milestone` (title or number), never `gh issue edit
   --milestone`; `Ready` is a status, never a label. The 2026-10-10 scan
   found clerks recovering from exactly these: a status in the wrong case or
   spacing in 22 runs, a milestone number passed to `gh` in 5, a `ready`
   label in 4.
9. **`no stamp` is a failure only where a stamp is due.** A drift check on
   an issue left in `Needs design`, or on a hub, that finds no stamp is
   reported as `no stamp (not Ready)`, not `FAILED` — those issues carry
   none by design, and the noise trained callers to skim the drift column
   (2026-10-11 scan: every `Needs design` child in afff5b02 flagged).

## Fold digest

| Date | Kind | Became |
|---|---|---|
| 2026-10-03 | friction | `parent:` / `parent: -` on existing issues (law 2); re-parent line reports the old parent's open-child count (law 5); grammar block mirrored in swarmify step 10 |
| 2026-10-03 | friction (59cf3f36) | handles resolved in new-issue bodies but not in comments on existing issues → law 2: every posted file is resolved, body or comment |
| 2026-10-06 | autopsy (b27f3a88) | eleven bodies shipped with raw `#@` tokens, one already `Ready` → the `#{name}` sigil the shim refuses (already landed) plus law 2's closing re-read |
| 2026-10-11 | owner + scans | manifest grammar → prose work order (law 2); vocabulary table (law 8); `no stamp` not a failure off `Ready` (law 9) |

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
| 2026-10-10 | corpus scan (54 sessions, 81 clerk runs; `docs/corpus/2026-10-10-swarmify-spec-weight-headless-clerk.md`) | `clerk.md` opened by the orchestrator in 25 of 54 sessions (22 before the grammar was mirrored into swarmify); final-report SKIPPED/FAILED 4 of 81 — 2 GraphQL quota, 2 manifest shape (a missing spec file; "no documented command to remove blockers"); in-run recoveries mostly vocabulary | 2, 8 |
| 2026-10-01 | reticle pass (#1284, six children) | creates, comments and body edits landed; then every `--add-blocked-by`, `milestone` and `issue view` died on "API rate limit already exceeded" — the hourly GraphQL quota, spent by `gh-project status <n>` reads at ~607 points each (now ~1). The clerk tried `sleep 60`, a `rate_limit` poll loop and backgrounded `gh-project` calls hung in the shim's backoff; the parent session finished by hand, links via REST `dependencies/blocked_by`. Owner: "The clerk charter updating to direct using REST first might be good nonetheless" | 7 |
