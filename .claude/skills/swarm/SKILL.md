---
name: swarm
description: Direct a team of parallel subagents through one pre-planned, parallelizable issue — decompose into file-disjoint units, dispatch each to an isolated worktree agent, then review and fast-forward each branch into master. Use when the user says "swarm #<n>", or asks to parallelize bulk/mechanical work across subagents. Only invoke as Opus, or as Sonnet when the plan is already written down.
---

# Swarm

One strong orchestrator, many fast workers. You do the thinking — decomposition,
review, merge. The workers do the typing, each in its own worktree, each with its
own context window.

The point is **context economy**. A swarm is worth running when the work would
otherwise fill your context with mechanical edits you don't need to remember. The
workers absorb that; you keep a lean session, so the user can still converse with
you while it runs.

> This is a **process** skill, and it is [`warp`](../warp/SKILL.md) with a fan-out.
> Read `warp`'s SKILL.md first — its rebase → `--ff-only` merge discipline applies
> here unchanged, once per worker branch, and is not repeated below. Read
> `.claude/rules/testing.md` too.

## Gate — do not swarm the wrong work

All four must hold. If any fails, use `warp` instead; a swarm on unsuitable work
costs *more* than doing it yourself, because you pay decomposition + N merges and
still end up reading the diffs.

1. **Pre-decided.** Every design question is already answered — in the issue, in a
   plan you just wrote, or in `docs/`. Workers cannot ask the user anything.
2. **Parallelizable into file-disjoint units.** See below. This is the hard one.
3. **Mechanical enough for a smaller model**, given red-green instructions: a
   failing test (or an exact spec) defines done.
4. **No human input mid-flight.** If the user must weigh in halfway, the swarm
   stalls with N worktrees open.

Being Opus is itself part of the gate. Sonnet may drive a swarm only when the
decomposition is already written down — not when it must be derived.

## The cycle

### 1. Resolve and plan

```bash
gh issue view <n> --comments
```

Then **think hard, before dispatching anything.** This is the step no worker can
do for you, and the step that decides whether the swarm succeeds. Produce, for
each unit: the files it owns, the acceptance test, and the exact instruction text.

### 2. Decompose onto disjoint files

**Two workers must never touch the same file.** Parallel edits to one file mean
the second rebase conflicts, and you've moved the work rather than saved it.

Partition by file, not by feature — features overlap, files don't. Write the file
list into each worker's prompt as an ownership boundary: *"you own exactly these
paths; if the task seems to need a file you don't own, stop and report it."*

Shared-file work (one `.tres` every unit must touch, a registry every unit
appends to) is **yours**. Do it in the main checkout before you dispatch, or as
an integration commit after you merge. Never hand it to two workers.

If the units don't come apart cleanly, that's a real answer: run `warp`.

### 3. Dispatch

Spawn every worker **in a single message** — that is what makes them run in
parallel. Per `Agent` call:

- `isolation: "worktree"` — mandatory. Without it, background workers edit the
  shared main checkout and collide with each other and with the user's WIP.
- `model: "sonnet"`, or `"haiku"` for ultra-mechanical work (rename, mass
  string-replace, boilerplate).
- `run_in_background: true`.
- The prompt must open with: **"Invoke the `drone` skill, then do the following."**
  `drone` carries the flow rules so you don't restate them N times. (Subagents do
  inherit the skill list — verified. If one ever reports it can't find `drone`,
  tell it to `Read .claude/skills/drone/SKILL.md` instead; it's plain markdown.)

Each `Agent` result hands back `worktreeBranch` and `worktreePath`. Record them —
they are your merge handles, and they're the only way back to a worker's commits.

Give each worker its acceptance test up front. A worker that can run
`mise run test:one -- res://test/unit/test_foo.gd` and see green knows it is done;
one that can't will report "looks right" and be wrong.

### 4. Collect

`drone` mandates a terse structured report. Read those, not the diffs. If a
worker's report is a wall of text, that's a `drone` violation — don't propagate
it into your summary to the user.

A worker that reports a blocker (needed a file it didn't own; test won't go green;
ambiguity in the spec) has done the right thing. Resolve it yourself, or re-dispatch
with `SendMessage` to that agent id — its worktree and context are still alive, and
continuing it is far cheaper than a cold respawn.

### 5. Review

You are the reviewer. The workers are smaller models and had no advisor.

```bash
git diff master...<worktreeBranch> --stat     # shape first
git diff master...<worktreeBranch>            # then read it
```

Verify the ownership boundary actually held (`--stat` shows any file a worker
shouldn't have touched) before you look at content. Nothing merges unreviewed.

### 6. Merge, one branch at a time

Per branch, in sequence, exactly as `warp` step 6 describes: rebase the branch
onto `master` from inside its worktree, then fast-forward `master`. Sequential is
not a limitation — each rebase re-tests the *next* branch against the merged
result of the previous ones, which is the only place a cross-unit break surfaces.

Run `mise run test` after each merge, not only after the last. When something
breaks, you want to know which branch did it.

If the units were file-disjoint, every rebase is clean. A conflict here means the
decomposition leaked — fix the decomposition's consequence, not just the conflict.

**Closing the issue:** worker commits must not carry `Closes #<n>` (whichever
merged first would close it early). Put it on your integration commit; if there
is none, amend it onto the final branch's tip commit before that branch's rebase.

### 7. Teardown

An `isolation: "worktree"` worktree is auto-removed only if the worker left it
unchanged — which is exactly the workers you *don't* need to clean up after.
Every worker that committed leaves one behind:

```bash
git worktree list                                   # find the survivors
git worktree remove .claude/worktrees/agent-<id>
git branch -d worktree-agent-<id>                   # -d, not -D: refuses if unmerged
```

Both plain forms work on a merged worker branch — reach for `--force` / `-D` only
once you know why the plain one refused. `remove` refuses while the worktree is
still `locked` (the agent hasn't exited) or dirty; `branch -d` refuses when the
branch isn't in `master`, which means you dropped a worker's work. Neither is a
formality to `--force` past.

## Gotchas

- **Worker worktrees live under `.claude/worktrees/agent-<id>/`, on branch
  `worktree-agent-<id>`** — not under `.worktrees/`, and not from
  `mise run worktree:new`. The harness creates them, branched from `master`'s tip
  at spawn time, and returns the path and branch in the tool result. That's the
  substrate; `mise`'s worktree tasks are for `warp`'s single-checkout cycle.
- **Workers branch from `master` as it was when they spawned.** Merging branch A
  moves `master`; branch B is now behind. That's why step 6 rebases each branch
  immediately before its own merge, not all of them up front.
- **Don't let a worker call `advisor`.** You are the advisor — you're the larger
  model and you hold the plan. `drone` tells them this; don't undercut it by
  suggesting it in a worker prompt.
- **A worker's context is not yours.** It cannot see this conversation, the issue,
  or the sibling workers' units. Everything it needs goes in its prompt: the
  files it owns, the acceptance test, and what "done" means.
- **Relay, don't paste.** The whole point is your context stays small. Summarize
  worker reports for the user in your own words; a swarm whose orchestrator pastes
  N diffs has spent its context anyway and saved nothing.
