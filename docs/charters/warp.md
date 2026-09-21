# Warp — charter

The design behind `.claude/skills/warp/SKILL.md`. The skill is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol. Sibling charters: [swarm](swarm.md) (which runs warp's
cycle at wave size N and mechanises its merge step as `mise run land`),
[drone](drone.md) (the leaf that inherits warp's red-green and ladder laws).

This charter was **mined from the working skill, not designed fresh**. The
skill was born 2026-07-02, before the charter convention, and was patched
with each lesson directly; every law below has a line in the skill it was
lifted from, and the skill has no paragraph that is not a law here. Owner,
2026-09-21: *"using the skills now seems to work very well"* — the point of
the charter is to capture *why* before anyone rewrites it, not to change it.

## What warp is for

Warp is the **single-issue trunk cycle**: one GitHub issue, one disposable
`git worktree`, one branch, driven from ticket to a fast-forwarded `master`
by one session with the owner as the merge gate. It is the repo's answer to
a main checkout that is a shared, un-worktree'd surface where several agents
may hold uncommitted WIP at once: unstaged edits there are unrecoverable, and
warp exists so that implementing an issue never has to touch them.

The three things warp owns and nothing else does: **the worktree lifecycle**
(create, work inside, tear down), **the fast-forward discipline** (rebase in
the worktree, advance `master` in place, never switch or stash the main
checkout), and **the approval gate** (nothing reaches `master` without the
owner's explicit go-ahead on a diff that is already green). Everything else
it composes: `gh` for the issue, `mise run worktree:*` for the checkouts,
`gh-project` for the board, the repo's testing and red-green rules for the
work in between.

## The cost model

Three costs shape the laws.

**The owner's review is the scarce step.** Approval is the one synchronous
hand-off in the cycle, and a diff that surfaces red tests or an unrebased
branch at approval time wastes it — the owner reads, decides, and then waits
for a fix they could have never seen. So the full suite runs *once*, before
approval, and the rebase precedes the ask.

**The full suite is a gate, not a feedback loop.** Measured across 248
transcripts (2026-08-19 → 2026-08-27): 464 full-suite runs, ~20.8 h of wall
clock, at a `test:one`-to-full ratio of ~2:1 where 10:1 is the target. A
suite run costs its output in context as much as its seconds in wall clock,
so the ladder — `check` (~20 s) → `test:one` → `test:dir` → suite — is what
iteration uses, and the suite is earned at final green, never to explore.
Sharding took most of the wall-clock pain away, not the size: the suite is
massive, the shards share the machine, and several agents running it at once
slow each other down without crashing the host — owner, 2026-09-21: *"the
suite IS big, massive even, but the sharding combats most of the wall clock
pains … which i think is the graceful option."* So the skill points at the
live figure in `CLAUDE.md` rather than quoting one, and the once-per-unit
rule holds regardless of how fast one run is.

**The merge token is serial by construction.** Warp advances the one local
`master`, so two warps (or a swarm's drones) serialise on it whatever their
approvals said; a branch rebased onto a `master` that moved is a tree nobody
tested. The rebase-then-ff shape keeps the window between "tested" and
"landed" as small as a by-hand procedure can; `mise run land` closes it
completely with a `flock` and a post-rebase `check` + `test:dir`, which is
why swarm routes every landing through it.

## Laws

**Set-up**

1. **One issue, one disposable worktree, all work inside it.** The worktree
   is created by `mise run worktree:new -- <n>` from the issue title, on a
   branch of the same name; creating it from a dirty main checkout is safe
   (it reads only `HEAD`), so the main checkout is never stashed or cleaned
   to make room. The main checkout is never edited during a warp.
2. **Resolve the issue before touching code.** Body and comments both — the
   comments usually narrow scope more than the title. A free-text query is
   matched against `gh issue list` or confirmed with the user, never
   guessed silently.
3. **Claim the board card on start.** `in-progress` the moment the worktree
   exists, so no other agent pulls the issue; moving it to `done` or
   `in-review` at merge time is optional (the `Closes` line does it on push).

**Work**

4. **Decide the test before the fix, and see it red.** The question is
   whether the change earns a test; "an exact behavioural spec" is the right
   answer for visual, tuning and refactor work, not a cop-out. A swarmified
   issue's acceptance spec names the test. When it earns one, the test comes
   first and is watched failing on *its own assert line* — a test file that
   references a not-yet-written `class_name` or method is a parse error GUT
   skips silently while reporting green, so the seam is stubbed, the cache
   refreshed if the name is new, and `test:one` confirmed to have *run* the
   file before the implementation starts.
5. **List what the test's setup has to reach into, before writing it.** A
   test of X that must write another unit's internals to arrange X's state
   has found a seam, not a fixture: who owns this fact, is this one thing
   pretending to be N, what does it cost per frame or at scale — answered
   from the plan, and the fix goes into the owner (or is filed against it),
   never into the unit that shows the symptom. The skill step carries this
   because a `paths:`-scoped rule cannot: Bash reads never fire one.
6. **A fresh worktree is a fresh checkout.** It has no `.godot/`; the first
   headless editor call cold-imports, and its cache is fully independent of
   the main checkout's (same "harmless during cold boot" script noise as a
   fresh clone at the same commit). A new or renamed `class_name` needs the
   worktree's *own* `mise run refresh`; the main checkout's does not
   propagate. Every `.claude/rules/*` applies unchanged.
7. **Climb the ladder; earn the suite once.** `check` after every script
   edit, `test:one` on the file, `test:dir` on the subsystem once it is
   believed green, and the full suite exactly once, at final green,
   immediately before asking for approval — never skipped (approval assumes
   green), never re-run mid-iteration.

**Landing**

8. **Approval is a hard stop.** Present the diff and summary and wait; no
   merge without an explicit go-ahead. `master` is shared state, and warp
   gets no exemption for having worked off to the side.
9. **Landing is one command.** `mise run land -- <branch> --closes <n>`,
   from anywhere in the checkout, after the go-ahead of law 8. It is laws
   10–12 mechanised: an exclusive lock so two landings serialise instead of
   racing the fast-forward; the rebase inside the branch's own worktree;
   `check` plus `test:dir` for every `test/unit/<dir>/` the branch touches,
   on the rebased tree — a rebased tree is a tree nobody tested; the
   fast-forward; the board card to in-review. Never the full suite inside
   it, never a push — both stay with whoever runs the train. The by-hand
   dance below is what `land` does, kept as the fallback for the one case
   `land` refuses by design.
10. **Rebase in the worktree, fast-forward in place, never touch the main
    checkout's working tree.** `git rebase master` inside the worktree —
    refs are shared, so it sees `master`'s real tip and rewrites only the
    warp branch, which then is a strict descendant and the merge a
    guaranteed fast-forward. `master` advances by `git merge --ff-only`
    from the main checkout, which tolerates unrelated dirty files and
    refuses only where a live edit overlaps the branch. `land` runs exactly
    this and refuses when the main checkout is parked off `master`; that is
    the by-hand fallback's only case — `git fetch . <branch>:master`
    updates the ref without a checkout and is ff-only by default. Never
    `git checkout master`, never `git stash`, never a `_merge` worktree,
    never `--no-ff`.
11. **`Closes #<n>` rides the tip commit.** `--closes <n>` amends it onto
    the tip right after the rebase when the message lacks it, so the tested
    sha is the landed sha — never an empty landing commit. By hand: amend in
    the worktree before the fast-forward.
12. **A refusal is signal, never an obstacle.** Each of `land`'s non-zero
    exits names one real cause, and each has one answer: no such branch, or
    the branch checked out in the main checkout (a worktree branch is the
    only thing it lands); main checkout off `master` (law 10's fallback, or
    ask); main checkout dirty in a file the branch also touches (someone's
    live WIP — surface it, never force past it); the branch's worktree dirty
    (commit first); a rebase conflict (aborted, files listed — resolve in
    the worktree, land again); a red `check` or `test:dir` (fix in the
    worktree, land again); a refused fast-forward (`master` moved under the
    rebase — land again). A second caller waits on the lock and says so;
    that is not a hang. Never `--force`, never a `+refspec`.
13. **Tear down.** `mise run worktree:rm -- <n>`, which confirms before
    deleting the branch. `.worktrees/` is gitignored; its contents are
    never committed.

**Shape of the skill**

14. **Compose, never restate.** The skill orchestrates `gh`, the
    `worktree:*` tasks, `gh-project`, and the testing / godot-workflow / red-
    green rules; it points at them and repeats none of their content. What
    those documents own, the skill links.
15. **No silent long-lived divergence.** A warp branch that is not done by
    end of day either merges back partial-but-functional — the incomplete
    piece commented out behind a `TODO(#<n>)` so `master` stays runnable,
    issue left open — or stays alive and is rebased onto `master` at least
    daily. Never a branch that drifts for days.

## Incident corpus

Each law traces to at least one of these. Kept here so the skill does not
have to carry them.

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-07-02 | #86 spike | the load-bearing unknown was whether Godot's per-checkout `.godot/` thrashes across worktrees; confirmed fully independent, and cold-boot script noise identical to a fresh clone at the same commit | 1, 6 |
| 2026-07-02 | #86 body | the owner's framing: "full local trunk based cycle … if not done EOD: merge back (but leave functional game, comment out offending lines) anyway or keep branch alive but rebase often, ideally just 1 main branch" | 8, 11, 15 |
| 2026-07-02 | birth | the first merge step used a disposable `_merge` worktree with stash/pop machinery so as never to touch the main checkout's branch | 10 |
| 2026-07-03 | merge rewrite | the merge step was self-contradictory — forbade touching the main checkout, then told agents to stash/merge/pop it — and merges flailed; a peer's uncommitted WIP was present in the main checkout mid-session during #86 itself, so the hazard was live, not hypothetical. Replaced by rebase + `--ff-only` / `fetch . <branch>:master`, verified empirically to tolerate unrelated dirty WIP and refuse only on a real local-edit overlap | 9, 10, 12 |
| 2026-07-14 | board | `gh-project` task landed; the claim step was added so a warped issue leaves Backlog/Ready before another agent picks it | 3 |
| 2026-07-30 | stale paragraph | the skill claimed `mise run check` was red repo-wide (~60 CoreHealthBar errors) and told agents to baseline-compare; no longer true, dropped whole — "no issue numbers, no paragraph" | 14 |
| 2026-08-03 | refresh | six sites (testing.md, manage-stats, drone, warp, swarm) still prescribed the raw `--editor --quit` command plus a hand `git diff`, the exact protocol `mise run refresh` replaced; and `--quit` could exit before a cold scan finished, so a "nothing changed" verdict could be a false negative | 6, 14 |
| 2026-08-28 | #649 | 464 full-suite runs in nine days (~20.8 h), `test:one`:full ≈ 2:1, one drone 66 test-family commands in 41 min; owner call: the suite is a gate, earned at most once per unit at final green, and the ladder is the feedback loop | 7 |
| 2026-09-03 | #710 warp drone | backgrounded the suite then polled it "madly" (`tail` / `ls` / `sleep`) until the owner intervened — the origin of the always-on `long-running-commands` breadcrule; warp inherits it rather than restating it | 14 |
| 2026-09-10 | red-green | warp said nothing about tests until step 4, post-hoc verification; drone's "Red-green" heading was a cost ladder in disguise; swarm assumed red-green instructions that did not exist. Test-first step added, substance to `docs/domain/red-green.md`, the parse-error-is-not-red trap named | 4, 14 |
| 2026-09-11 → 15 | #857 | the merge token mechanised as `mise run land` (`flock`, rebase in the worktree, `check` + `test:dir` on the rebased tree, ff-only, board move) because "a rebased tree is a tree nobody tested"; swarm routes every landing through it and cites warp for the discipline it encodes | 9, 10 |
| 2026-09-17 | seven redirects | seven owner redirects in seven days were all answerable from the plan sentence, none from the diff — a red test that poked another unit's state to move a goalpost; the coupling questions went into warp's test step because Bash reads never fire a `paths:` rule, so the skill step is the carrier | 5 |
| 2026-09-21 | owner | "using the skills now seems to work very well" — so this charter is mined from the file, not designed, and the skill is patched, not rewritten | all |
| 2026-09-21 | git history | `.claude/agents/sage.md` was born 2026-09-11 and its charter landed 2026-09-17; swarm's and swarmify's charters landed 2026-09-15 with their skill files touched the same day. Warp's skill was born 2026-07-02 with no charter and was patched with lessons directly, so its laws lived only in prose — the filing session's grounds for this issue | all |
| 2026-09-21 | #1020 | step 6 still prescribed the by-hand rebase / ff dance six days after `land` mechanised it; owner: "warp may lag in this and could use mise run land, it's a pure efficiency upgrade right? not all agents are bash-golfers supreme so doing a mechanical job of multiple steps exactly right every time using 1 command is great to have" — laws 9–12 re-derived around `land`, the by-hand form kept only as the off-master fallback, its refusal list carried as the signal it is | 9, 10, 12 |

## What the skill must not contain

- Any row above, any issue number, any date, any "verified empirically" /
  "confirmed during" attribution — the fact stays, the provenance moves here.
- The measurement tables: the #649 counts, the suite's script/test counts.
  The live suite cost lives in `CLAUDE.md`; the skill names the ladder, not
  the figures.
- Restatements of always-on rules the session already carries:
  `long-running-commands` (launch once, no poll, end the turn),
  `red-green`'s substance, `testing-tiers`, the git-gotchas (`git -C` never
  cwd, explicit-path `git add`, an explicit sha on push — warp never
  pushes, so the last is not warp's at all).
- The `worktree:*` task internals, the `land` task's protocol, the
  `gh-project` subcommand list — each is owned by `mise.toml` or its task
  file and linked, not copied.
- History of what the merge step used to be — the by-hand two commands
  before `land`, the `_merge` worktree before those. `land` is the law, the
  fallback is one sentence; why the old ones flailed is the rows above.

## Open follow-ups

- `relief` (#1022, a revision first) still carries warp-shaped dated lore
  and no charter; `handoff` lacks one too.
