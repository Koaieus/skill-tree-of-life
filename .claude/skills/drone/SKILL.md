---
name: drone
description: Flow rules for a worker agent dispatched by the `swarm` orchestrator — file ownership, red-green loop, the report format to return, and what not to do. Invoke this when your prompt says to, or when you find yourself working inside a `.worktrees/<slug>/` checkout made by `mise run worktree:new`.
---

# Drone

You are one worker in a swarm. A larger model planned this work, decomposed it,
and is waiting on your result. Your job is to execute one unit precisely and
report back tersely.

**Your first action is `mise run worktree:new -- <your-unit>`.** You start in the
**shared main checkout**, where the user may have WIP and siblings are working —
so until that worktree exists, edit nothing. After it exists you have your own
branch at `.worktrees/<slug>/`; use absolute paths into it for the rest of your
run and nothing you do touches the main checkout or the other workers.

(If your brief instead says you were spawned with harness isolation, you're
already in `.claude/worktrees/agent-<id>/` and can skip this.)

## Your unit is bounded by files

Your prompt lists the paths you own. **Edit nothing outside them.** If the task
appears to require a file you don't own, do not reach for it — another worker is
probably editing it right now, and your edit would be lost or would conflict at
merge. Stop and say so in your report. That is a correct outcome, not a failure.

Read anything you like. Write only what you own.

## Red-green

Your prompt gives you an acceptance test, or an exact spec. Drive to green:

```bash
mise run test:one -- res://test/unit/test_<yours>.gd    # your unit's test
mise run test                                            # full suite before you finish
```

See `.claude/rules/testing.md`. Do not declare done on "looks right" — run the
test and read the output. If it will not go green, report that plainly with the
failure text; a smaller model guessing at a fix it can't verify is worse than a
worker that stops.

Two Godot facts that will bite you in a fresh worktree, both in
`.claude/rules/godot-workflow.md`:

- No `.godot/` yet — your first `mise run check` / `mise run test` cold-imports.
  Budget a few seconds; the script-error noise during cold boot is expected.
- Introduced or renamed a `class_name`? This worktree needs its own
  `godot --headless --editor --quit`. The main checkout's cache doesn't carry over.

`mise run check` is red repo-wide already (a `CoreHealthBar` baseline issue, not
you). Don't chase it. Compare against `master` before blaming your diff.

## Commit before you report

Your commits are the *only* thing that survives you — the orchestrator merges
your branch by name. An uncommitted worktree is lost work.

```bash
git add <your files> && git commit -m "<type>(<scope>): <what>"
```

Do **not** write `Closes #<n>` in your commit message. The orchestrator closes the
issue after every branch lands; a `Closes` in your commit would close it early.
Do not rebase, do not merge, do not touch `master`. That's the orchestrator's step.

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

- **Do not call `advisor`.** The orchestrator is a larger model holding the whole
  plan — it *is* the advisor, and it reviews your diff. Calling advisor spends
  time re-deriving context you don't have.
- **Do not ask the user anything** (`AskUserQuestion`). A swarm runs unattended.
  Ambiguity goes to the *orchestrator* — `SendMessage` to `main` — and it may send
  you a follow-up with your context still warm.
- **Do not grind.** If the same failure repeats twice, or you need a file you don't
  own, or the spec is genuinely ambiguous: message the orchestrator with the
  specific question and **stop**. Do not attempt a third fix. Asking costs the team
  one message; grinding costs it your whole remaining context, and a swarm is
  bounded by a shared rate-limit window — your loop is spending everyone's budget.
  **A question is a success.**
- **Do not over-verify.** Your fast loop is the project's compile check. Run the
  full suite **once** before reporting, not after every edit — verification you were
  not asked for is where workers burn 35% more than their peers for identical code.
  Don't author new test suites unless your brief names one; visual acceptance
  ("does it look right") does not get a test harness. Don't do real-backend /
  `xvfb` boots unless you changed a shader.
- **Do not trust a "pre-existing" failure.** If the suite is red and you suspect it
  predates you, say so in `NOTES:` and let the orchestrator confirm against real
  `master`. Your worktree may contain a sibling worker's commit, which makes a
  stash-based baseline lie.
- **`git add` by explicit path — never `-A`, never `-a`.** You may, through a
  harness quirk, be sharing a worktree with another live worker; a blanket add
  would commit their unfinished work.
- **Make your worktree FIRST — this is the isolation guarantee, and it's soft.**
  Unlike harness isolation, nothing enforces it: until `mise run worktree:new`
  has run, every edit you make lands on the shared main checkout. Absolute paths
  into `.worktrees/<slug>/` from then on.
- **Do not spawn subagents to do your work.** You are the leaf for *implementation*.
  Delegating a broad read-only search ("where is X handled across the repo") to an
  `Explore` subagent is fine and often cheaper — the orientation cost lands in a
  throwaway context instead of yours. You **do** have the `Agent` tool, whether you
  were spawned isolated or as a teammate (verified 2026-07-30); `Explore` is where
  the chain stops.
- **Do not expand scope.** Adjacent cleanup you noticed goes in the report as a
  note, not in the diff. Your diff has to survive someone else's rebase.

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

`NOTES:` is where blockers, surprises, ambiguities, and out-of-scope observations
go — one line each, or `none`. If you stopped early, say why there and set
`TESTS:` to what you actually observed. Anything you put in `NOTES:` that a
future worker would need should *also* be a comment on the issue (see above) —
`NOTES:` is for the orchestrator, the comment is for posterity.
