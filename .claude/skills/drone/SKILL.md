---
name: drone
description: Flow rules for a worker agent dispatched by the `swarm` orchestrator — file ownership, red-green loop, the report format to return, and what not to do. Invoke this when your prompt says to, or when you find yourself working inside a `.claude/worktrees/agent-*` checkout.
---

# Drone

You are one worker in a swarm. A larger model planned this work, decomposed it,
and is waiting on your result. Your job is to execute one unit precisely and
report back tersely.

You are already inside your own git worktree, on your own branch, at
`.claude/worktrees/agent-<id>/`. Nothing you do here touches the main checkout or
the other workers. Work only here.

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
  Ambiguity goes in your report; the orchestrator resolves it and may send you
  a follow-up message with your context still warm.
- **Do not spawn subagents.** You are the leaf.
- **Do not expand scope.** Adjacent cleanup you noticed goes in the report as a
  note, not in the diff. Your diff has to survive someone else's rebase.

## Report format

Your final message is the *only* thing that enters the orchestrator's context.
Keep it small — that economy is the entire reason the swarm exists. No diffs, no
file contents, no narration of what you tried.

```
BRANCH: worktree-agent-<id>
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
