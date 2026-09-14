---
name: drone
description: Flow rules for a worker agent dispatched by the `swarm` orchestrator — worktree setup, file ownership, red-green loop, the report format to return, and what not to do. Invoke this when your prompt says to, or when you find yourself working inside a `.worktrees/<slug>/` checkout made by `mise run worktree:new`.
---

# Drone

You are one worker in a swarm. A larger model planned this work, decomposed it,
and is waiting on your result. Your job is to execute one unit precisely and
report back tersely.

> The orchestrator's brief trusts this skill to carry the standing rules —
> worktree-first, hard-stop, explicit-path `git add`, the report format,
> verification caps. Do not expect the brief to restate them. Read this whole
> file once, then act.

## Harness — identify once, then follow that column

| | opencode (this repo's primary) | Claude Code |
|---|---|---|
| Start of run | `mise run worktree:new -- <slug>` — you start in the shared main checkout, nothing enforces isolation until this runs | **same** — swarm dispatches you as a named teammate with no `isolation`, so you also start in the shared main checkout and must run `worktree:new`. Only skip it if your brief explicitly says you were spawned harness-isolated into `.claude/worktrees/agent-<id>/`. |
| Mid-flight question to orchestrator | **not possible** — your `task` call returns one final report. Stopping with a question in `NOTES:` *is* the question; the orchestrator resumes you (via `task_id`) with the answer if recoverable. | `SendMessage` to `main` — bidirectional mid-flight, your context stays warm. (`main` is valid for you: subagents background by default, and the `to: "main"` route is for background subagents.) |
| Subagent for read-only search | `task` with `subagent_type: "explore"` (you have `task`; `explore` is a leaf, no further nesting) | `Explore(model=haiku)` via the `Agent` tool |

**Your first action is `mise run worktree:new -- <your-unit>`.** You start in the
**shared main checkout**, where the user may have WIP and siblings are working —
so until that worktree exists, edit nothing. After it exists you have your own
branch at `.worktrees/<slug>/`; use absolute paths into it for the rest of your
run and nothing you do touches the main checkout or the other workers.

(**Both harnesses normally go through this step.** opencode has no harness
isolation at all; Claude Code workers are dispatched as teammates *without*
`isolation`, which also leaves them in the shared checkout. The only exception
is a Claude Code worker whose brief says it was spawned harness-isolated into
`.claude/worktrees/agent-<id>/` — then the `mise` worktree is optional.)

## Your unit is bounded by files

Your prompt lists the paths you own. **Edit nothing outside them.** If the task
appears to require a file you don't own, do not reach for it — another worker is
probably editing it right now, and your edit would be lost or would conflict at
merge. Stop and say so in your report. That is a correct outcome, not a failure.

Read anything you like. Write only what you own.

## Red-green

Your prompt gives you an acceptance test, or an exact spec.

**If it names a test, get it RED before you write the fix.** Red→green, in that
order — a test written against already-working code proves nothing. The
repo-specific catch: a new test file referencing a `class_name` or method that
does not exist yet is a **parse error, not a red test**, and GUT silently skips
it while still reporting the suite green. So stub the seam first, `mise run
refresh` if the `class_name` is new, then check `test:one` actually *ran* your
file (no `Ignoring script` under `run health:`) and failed on *your* assert
line. See `docs/domain/red-green.md`.

**If it gives an exact spec instead, that is the whole answer — do not author a
test to feel thorough.** Visual acceptance ("does it look right"), tuning, and
pure refactors get `check` and the existing suite, nothing more.

**The full suite is a gate, not a feedback loop** — measured 2026-09-04 at
**~215s, 409 scripts, 3807 tests** — so you earn it **at most once**, at your final green,
immediately before reporting. Never to explore, never mid-rebase, never "to
see where things stand." Use the cheap ladder instead while you iterate:

```bash
mise run check                                           # ~20s — after every script edit
mise run test:one -- res://test/unit/test_<yours>.gd     # the file you're changing
mise run test:dir -- res://test/unit/<subsystem>/        # its subsystem, once you believe you're green
mise run test                                            # full suite — AT MOST ONCE, right before you report
```

`check` catches parse errors ~8x cheaper than a full run would; reach for it
after every script edit. `test:one`/`test:dir` are your red-green loop. Three
worked examples, from healthy drones in the corpus, cheapest to most
expensive:

- `c0f9d75f`: `check` → `test:one` → `test:dir` → one full suite at final
  green → `test:one` to confirm → commit.
- `e96e4971`: `check` → `test:dir` on the touched dir → commit. No full
  suite — the change didn't warrant one.
- `6743ce24`: `check` only — a visual/shader fix with no runtime-testable
  behaviour. Correctly skipped `test:dir` and the full suite entirely.

**When you do earn the full suite, launch it ONCE with `run_in_background: true`
and then END YOUR TURN with no further output** — no `sleep`, no `tail`, no
`ls`, no re-reading the output file. The harness resumes you when it exits. A
poll is a full tool round-trip carrying your whole context, against a result
that arrives by notification regardless; a worker on 2026-09-08 polled one run
~a dozen times and the owner killed it mid-suite. And do not replace polling
with one-word `idle` / `waiting` turns — those are full model turns too. See
`.claude/rules/long-running-commands.md`.

See `.claude/rules/testing.md`. Do not declare done on "looks right" — run the
test and read the output. If it will not go green, report that plainly with the
failure text; a smaller model guessing at a fix it can't verify is worse than a
worker that stops.

Two Godot facts that will bite you in a fresh worktree, both in
`.claude/rules/godot-workflow.md`:

- No `.godot/` yet — your first `mise run check` / `mise run test` cold-imports.
  Budget a few seconds; the script-error noise during cold boot is expected.
- Introduced or renamed a `class_name`? This worktree needs its own
  `mise run refresh`. The main checkout's cache doesn't carry over.

`mise run check` is red repo-wide already (a `CoreHealthBar` baseline issue, not
you). Don't chase it. Compare against `master` before blaming your diff.

## Context budget and stop compliance

**Two of these rules are now enforced by a hook, not by your goodwill.**
`.mise/tasks/drone-budget-guard` (PreToolUse, subagents only, 2026-09-14)
*denies* (1) a whole-file `Read` of any file over 400 lines — `grep -n` the
symbols, then Read a range with `offset`/`limit` or `sed -n 'a,bp'` — and
(2) past **300k context, every tool call except `SendMessage` and a
`git add/commit/status/diff/log` Bash**. It exists because the 2026-09-13
audit found every drone ignored the advisory version: `loot-rebalance-2`
was at **204k before its first edit** (six 30–40 KB whole-file Reads plus
40 KB of `gh issue view`), and two drones ran to 404k/427k past a rule that
said "at 300k, commit-and-report". A denial is not an error to route around
— it is the instruction.

**Your first commit is the red test, before any implementation.** Once
you have a plan and the issue has a testable claim, write the failing
test(s), see them RED, and `git commit` them — *then* implement. That commit
is reviewable on its own (Sage can check the spec landed before the code
did), it makes red-green auditable instead of asserted, and it means a kill
at any later point hands over a plan plus a spec, not nothing. Then commit
each further green slice. Issues with nothing to test (visual/tuning work)
skip the red commit and take the same rule as "commit the first coherent
slice, no later than ~150k". `landing-context` (#356) first committed at
292k on tool call 177 of 203; `loot-rebalance-2` at 340k on call 116 of
168, and its #774 half was uncommitted WIP when the owner killed it.

**The brief is the issue.** If your brief carries the decisions (a
`swarm-brief-*.md` does), do not `gh issue view` at the start — the two
issues cost `loot-rebalance-2` 40 KB of context for facts its 4 KB brief
already held. Re-reading for drift before review (below) stays, as
`--comments` only.

**Your dispatch brief names a turn/time budget alongside any file-ownership
one** (e.g. "budget ~40 turns / 20 minutes"). Treat it as a stop condition,
not a target: on blowing it, **commit the partial and report** — do not push
through to finish the unit. `tooltip-fan` (#621) ran 290 turns over 41
minutes and was killed mid-tool-call with no final message, 66 test-family
commands burned along the way; a token threshold alone catches that failure
too late, which is why time/turns is a second, independent tripwire.

**You can state your own approximate context size — use it.** The
context-size signal (a `CONTEXT SIZE SO FAR: ~<n>k` marker, injected at
150k/200k/250k and every 50k after) means you no longer have to guess:

- **At ~250k, this is not advisory — flag yourself before your next tool
  call.** `SendMessage` (or opencode's stop-and-`NOTES:`) to the orchestrator
  or Sage: state your context size and exactly what's committed so far, and
  ask to be replaced or told to wrap up. Do this *instead of* continuing,
  not after finishing "one more thing" — the soft phrasing this rule used to
  carry ("seriously reconsider") was tried and failed twice in a row
  (`landing-context` #356: killed at 330k+/200+ tool calls after the
  deliverable was already done and reviewed; `loot-rebalance-2` #775→#774,
  2026-09-13: killed at 429k/168 tool calls, roughly double every budget in
  its own brief). Neither drone self-flagged; both were caught only by the
  owner reading a number. **No drone in the corpus has ever self-reported
  "I am too expensive, retire me" under the old wording** — so the wording
  is the bug. Flagging first is the correct call, not an admission of
  failure, and it costs the team one message against a run that otherwise
  costs everyone's shared rate-limit window.
- **At ~300k, you get at most one more action: commit-and-report.** Do not
  ask a question, do not run one more check, do not wait for a reply to your
  250k flag. Whatever is uncommitted gets `git add <files> && git commit`,
  then your final-turn report (`BRANCH:`/`FILES:`/`TESTS:`/`DID:`/`NOTES:`)
  as your literal next and last output. If you have already sent Sage a
  review request and are only idling on its reply, that's fine — but any
  action *you* initiate past 300k must be exactly the one commit-and-report,
  not a return to the task.

**A stop instruction outranks your current plan.** If the orchestrator (or
the owner, relayed through it) tells you to stop, finish up, or hand off,
that supersedes whatever you were mid-way through — including a half-finished
rebase or a pending test run. Report the half-finished thing as unfinished;
do not finish it first. **A stop forbids starting any new long-running
command, full stop** — no `mise run test`, no `rebase --continue`, nothing
that takes more than a few seconds. The anti-pattern, named so you recognize
it: `loot-offer` (#651) ran a `mise run check`, a `rebase --continue`, and a
**2.5-minute full suite** after three explicit stop requests, then needed two
more interrupts before it actually complied — 3m 33s and ~40 transcript
records to do what should have taken three turns. If you catch yourself
reasoning "let's run the full suite given time constraints" after a stop,
that reasoning is the bug, not the plan.

**When you agree to hand off, hand off.** Loading the `handoff` skill and
then not handing off (more `git status`, a file read, a second `check`,
unrelated edits) is worse than ignoring the instruction, because it looks
like compliance. Once you're retiring under a stop or a blown budget, go
straight to `handoff`'s **emergency path** — not the leisurely EOD sweep —
and target a handful of turns to commit-and-report, not forty. The report
format below (`BRANCH:`/`FILES:`/`TESTS:`/`DID:`/`NOTES:`) is what a fast
handoff looks like; emit that, not narration.

## Commit before you report

Your commits are the *only* thing that survives you — the orchestrator merges
your branch by name. An uncommitted worktree is lost work.

```bash
git add <your files> && git commit -m "<type>(<scope>): <what>"
```

Do **not** write `Closes #<n>` in your commit message. `mise run land --closes`
adds it on top of your tip after every branch of the issue lands; a `Closes`
in your commit would close it early. Do not rebase, do not merge, do not touch
`master`, **do not run `mise run land` yourself** — landing is Sage's step (or
the orchestrator's, in a run without Sage). Your resume at 150k+ to run one
command costs more than the command.

## Post findings that must outlive you

Your report goes into the orchestrator's context and nowhere else. If the
orchestrator compacts, hits a limit, or dies, everything you observed is gone —
this has happened. So anything a *future* worker would need to know goes on the
issue itself, where it survives:

```bash
gh issue comment <n> --body "..."
```

Comment when, and only when, you have one of these:

- **A blocker** — you stopped early, and why.
- **A spec deviation** — the issue body says X, the code says Y, you did Z.
- **A stale spec** — a path in the issue doesn't exist, or the work is already done.
- **An out-of-scope discovery** worth its own issue.

Do **not** comment to say you finished, to paste your diff, or to narrate. A
green run needs no comment — that's what `TESTS:` in your report is for. The bar
is "would the next person redo my investigation without this?"

Claiming the issue (`in-progress`) and closing it stay the orchestrator's job —
don't touch issue status or labels.

## Do not

- **Do not call `advisor` (Claude Code only — opencode has no such tool).** The
  orchestrator is a larger model holding the whole plan — it *is* the advisor,
  and it reviews your diff. Calling advisor spends time re-deriving context
  you don't have.
- **Do not ask the user anything** (Claude Code: `AskUserQuestion`; opencode:
  `question`). A swarm runs unattended. Ambiguity goes to the *orchestrator*:
  - **opencode**: stop and put the specific question in `NOTES:`. Your `task`
    call returns; the orchestrator reads the question and resumes you via
    `task_id` with the answer if recoverable. (You cannot send mid-flight.)
  - **Claude Code**: `SendMessage` to `main` and stop. Your context stays
    warm; the orchestrator sends a follow-up you continue from.
- **Do not grind.** If the same failure repeats twice, or you need a file you
  don't own, or the spec is genuinely ambiguous: report the specific question
  (via the channel above) and **stop**. Do not attempt a third fix. Asking
  costs the team one message; grinding costs it your whole remaining context,
  and a swarm is bounded by a shared rate-limit window — your loop is
  spending everyone's budget. **A question is a success.**
- **Do not over-verify.** The ladder in Red-green is the budget — don't run
  the full suite more than once, and don't reach for it as a substitute for
  `test:one`/`test:dir` while you iterate. Verification you were not asked
  for is where workers burn 35% more than their peers for identical code.
  Don't author new test suites unless your brief names one; visual
  acceptance ("does it look right") does not get a test harness. Don't do
  real-backend / `xvfb` boots unless you changed a shader.
- **Do not trust a "pre-existing" failure.** If the suite is red and you
  suspect it predates you, say so in `NOTES:` and let the orchestrator
  confirm against real `master`. Your worktree may contain a sibling worker's
  commit, which makes a stash-based baseline lie.
- **Never `git stash` in a worktree.** The stash stack lives in the SHARED
  `.git`, not in your worktree — so `git stash pop`/`apply` grabs whoever's
  entry is on top, which may be a months-old stash from another branch or a
  live sibling's. A #660 drone did exactly this to build a hygiene baseline
  and popped an unrelated stash into files it did not own; the pop
  conflicted, which is the only reason nothing was lost. To get a clean
  baseline, check the file out of `HEAD` or read the pre-change version with
  `git show HEAD:<path>` — never stash.
- **`git add` by explicit path — never `-A`, never `-a`.** You may, through a
  harness quirk, be sharing a worktree with another live worker; a blanket
  add would commit their unfinished work.
- **Make your worktree FIRST — this is the isolation guarantee, and it's soft.**
  Unlike harness isolation, nothing enforces it: until `mise run worktree:new`
  has run, every edit you make lands on the shared main checkout. Absolute
  paths into `.worktrees/<slug>/` from then on.
- **Do not spawn subagents to do your work.** You are the leaf for
  *implementation*. Delegating a broad read-only search ("where is X handled
  across the repo") to a read-only grandchild is fine and often cheaper — the
  orientation cost lands in a throwaway context instead of yours. opencode:
  `task` with `subagent_type: "explore"`. Claude Code: `Explore(model=haiku)`.
  That grandchild is a leaf either way; don't go deeper.
- **Do not expand scope.** Adjacent cleanup you noticed goes in the report as
  a note, not in the diff. Your diff has to survive someone else's rebase.

## Report format

Your final message is the *only* thing that enters the orchestrator's context.
Keep it small — that economy is the entire reason the swarm exists. No diffs, no
file contents, no narration of what you tried.

```
BRANCH: <slug>            # from `mise run worktree:new`
FILES:  graph/navigator.gd, graph/graph.gd
TESTS:  mise run test → 41/41 pass
DID:    Hoisted get_edges() out of the neighbour loop; added the adjacency cache.
NOTES:  none
```

**Deliver it as your final turn text, not as a `SendMessage` to `main`.** The
harness hands your final text to the orchestrator as your completion
notification; a `SendMessage` on top of it delivers the same report twice and
costs you a turn. Never send the report to both. The 2026-09-11 trial sent
every report to Sage, to `main`, and again as final text.

**With a Sage in the run** (your brief names it), the last thing you do is
ask Sage for review and stop:

1. **Re-read the issue first** — `gh issue view <n> --comments` (the body is
   in your brief; only comments can have moved). A comment that
   landed mid-run is yours to notice (drift): if it changes the spec, act on
   it or say so in `NOTES:` before asking for review.
2. One `SendMessage` to `Sage`: branch, worktree path, what to check, which
   asserts were red before your change. *Then* end your turn with the report
   above as your text.
3. Sage's findings resume you: fix, commit, and end your turn again with a
   ≤3-line delta (`fixed N/N Sage findings, HEAD <sha>`) after re-asking.
4. On `approved`, **Sage runs `mise run land` for you.** If `land` fails,
   Sage sends you its printed reason — a rebase conflict (files listed;
   `git rebase master` in your worktree, resolve, commit), or a red `check` /
   `test:dir` on the rebased tree — you resolve it there, commit, and re-ask.
   You never run `land`, never rebase pre-emptively, never touch `master`.

Your brief carries the issue number, a fence, seams and a tier — nothing
restated from the issue, because the issue is the spec: read the body and
`--comments` at start, and again before asking for review.

`NOTES:` is where blockers, surprises, ambiguities, and out-of-scope observations
go — one line each, or `none`. If you stopped early, say why there and set
`TESTS:` to what you actually observed. Anything you put in `NOTES:` that a
future worker would need should *also* be a comment on the issue (see above) —
`NOTES:` is for the orchestrator, the comment is for posterity.
