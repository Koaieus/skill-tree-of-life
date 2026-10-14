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

The third stretch of the same shape is the end of a **feedback fold pass**
(README → *Feedback boards*): the charter is edited and committed, and what
is left is one `feedback reply --resolve` per post, each verdict line
already written. Owner, 2026-10-12: *"maybe use a clerk to manage the
discussions"*. Same clerk, same order format, one more verb.

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
   makes. A new issue is created with its body in the same call; only a
   body that names a sibling not yet created goes up as a stub and is
   filled once every number exists, so no forward handle is ever posted.
   (Was stub-then-fill for every new issue; owner, 2026-10-11, after the
   law-10 autopsy: *"clerks are so cheap it's literally 1/10th the cost of
   Fable so they might as well post bodies literally if they got them
   right. or do some bulk edits sure but it's not as needed"* — the second
   call bought nothing but a step to drop.) The sigil was `@name`
   until a leftover `#@`-handle in #1383 pinged a stranger (owner,
   2026-10-08: *'"@"s were a really bad pick for handles, fixing that
   forever'*); the gh shim refuses both a bare `@name` and an unresolved
   `#{name}`. Before reporting, the clerk re-reads every body and comment it
   posted and confirms no `#{` survives.
   **The order may be the spawn prompt itself** (2026-10-14, with law 12):
   plain prose inline, or a path to a file holding the same prose. The file
   form stays for when body files already exist beside it (spec bodies —
   relative paths resolve against the order's directory); an inline order
   names any file by absolute or repo-root-relative path. A short comment
   is written *in* the order — `comment "Triage (owner, 2026-10-14): …"` —
   and the clerk writes it to a temp file itself (a quoted heredoc, so
   backticks survive) and posts it with `--body-file`; inline comment text
   gets the same handle pass as a file. Was: a scratch file per comment,
   written by the parent, which cost the parent a turn per file.
3. **Every exit code is checked; nothing is piped through `tail`; nothing is
   retried blind.** The
   issue-workflow traps (`--add-parent` swallowed by a pipe, `blockedBy` as an
   object, the raw dependencies API taking internal ids, backticks in `--body`, a
   remembered `--json` field name that has since moved)
   all fail *silently*; the clerk's instructions carry each one so the spawning
   session does not have to.
4. **Board rules are enforced by refusal, not repair.** No `Ready` without a
   milestone, no status on a hub, no reopen/retitle, no git. An order that
   asks for one gets a `SKIPPED` line. **A close the order names is the
   clerk's** (superseded in place, 2026-10-14): the line gives the reason
   (`not planned` | `completed` | `duplicate of #m`) and the comment text,
   and the clerk posts the comment then closes with that reason; a close
   line missing either is `SKIPPED` (law 1: a missing datum is not
   guessed). Closes for landed work still come from the push footer
   (`land --closes`, `Closes #n` fires on push); the clerk closes only what
   the order names, which is the triage routes — not planned, already
   fixed, duplicate — that no commit backs. *Rejected grounds of the old
   ban:* a clerk close would duplicate or race the push footer (true only
   for landed work, which no order will name), and closing felt like a
   content call (it is not once the order carries the reason and the
   words). Owner, 2026-10-14: *"Clerks not closing means a more expensive
   model must."*
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
   `intake | backlog | needs-design | ready | in-progress | in-review |
   done` (an order naming no status leaves a new issue in `Intake`;
   priorities are `p0..p4`),
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
10. **A body is verified against the order, by length.** A stub *looks*
    filed: a dropped fill leaves an issue with a title, labels, parent and
    status, and nothing to read. So a new issue is created with its body
    (law 2), a stub is the forward-handle exception and says what it is
    (`Clerk stub — body not posted yet.`), and the verify pass walks the *order's* body files,
    not the clerk's memory of its own posts — reads back each body's length
    against its `.resolved` file and fails the line when it is still the
    stub or shorter. The new-issue report line carries `body <file>
    <got>/<want>c`, so a missing body shows as a missing field, not silence.
    A self-referential check ("re-read what you posted") passes vacuously on
    a post that never happened.
11. **A fold order is replies, nothing else.** Each line names a comment id
    and a reply file whose text the folder wrote (`folded in <sha>: …` or
    `rejected: …`); the clerk runs `mise run feedback -- reply --resolve
    <id> <file>` per line, then `feedback -- unanswered <charter>` per board
    touched, and reports `<id> replied+resolved` or the failure. It never
    writes a verdict, never edits a charter, never replies to a post the
    order does not name — a post still unanswered afterwards is reported,
    not answered.

12. **The parent spends one turn on the clerk spawn.** The order is written
    in the `Agent` call's prompt, in the same message as whatever else the
    parent dispatches; no scratch files, no path to pass, no turn spent on
    `Write` before the spawn. Owner, 2026-10-14: *"Clerks are just here to
    turn 1 prompt by parent into N dirt cheap turns by Haiku. Esp if no
    thinking is needed, just mechanical or sequential steps. And the '1
    turn prompt' is in practice already violated often with agents taking
    a few turns to write out prompts to scratch files n whatnot before
    posting it to Clerk"*. The file form (law 2) is for bodies that exist
    anyway, not for the order.

## Fold digest

| Date | Kind | Became |
|---|---|---|
| 2026-10-03 | friction | `parent:` / `parent: -` on existing issues (law 2); re-parent line reports the old parent's open-child count (law 5); grammar block mirrored in swarmify step 10 |
| 2026-10-03 | friction (59cf3f36) | handles resolved in new-issue bodies but not in comments on existing issues → law 2: every posted file is resolved, body or comment |
| 2026-10-06 | autopsy (b27f3a88) | eleven bodies shipped with raw `#@` tokens, one already `Ready` → the `#{name}` sigil the shim refuses (already landed) plus law 2's closing re-read |
| 2026-10-11 | owner + scans | manifest grammar → prose work order (law 2); vocabulary table (law 8); `no stamp` not a failure off `Ready` (law 9) |
| 2026-10-11 | autopsy (52517a89) | two new issues left on the stub body, reported clean → law 10: body fill named per issue in step 3, self-describing stub, verify by length against the order's files, `body <file> <got>/<want>c` on the report line; then owner: create with the body, stub only for a forward handle (law 2) |
| 2026-10-12 | owner | the fold pass's reply tail goes to the clerk → law 11, `feedback reply --resolve` |
| 2026-10-14 | owner (triage review) | the clerk closes what the order names, with reason and comment (law 4 superseded in place); the order may be the spawn prompt, comments inline (law 2); the parent spends one turn on the spawn (law 12) |

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
| 2026-10-11 | /swarmify #1254 (Scout row), clerk in 52517a89 | the order said "body lantern.md" / "body statshape.md" for two new issues; the clerk created #1557 and #1558 with the stub "Spec follows.", resolved and posted only the #1393 comment (the one file the order said had handles), re-read only that comment, and reported both creates clean with no SKIPPED/FAILED. The owner found it opening #1558 in a fresh swarmify session; bodies repaired by hand | 10 |
