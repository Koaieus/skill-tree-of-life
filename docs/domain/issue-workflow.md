# Issue tracking & the project board

The full version of `CLAUDE.md` → *Issue tracking*. Read this before running
`mise gh-project`, filing an issue, swarmifying, or dispatching a drone.

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`). Labels: `core`,
`design`, `blocked` (open upstream fork), plus defaults.

## The board

`mise gh-project -- list|add|status|priority|size`. `list
[backlog|needs-design|ready|in-progress|in-review|done|all]` shows a column —
that's how an agent finds work to pick up; add `--json` (with `mise run
--quiet`) for machine-readable output. See `.mise/tasks/gh-project`.

`add` already lands the new issue in `Backlog` — no follow-up `status` call
needed unless you actually want a different lane (e.g. straight to
`needs-design` or `ready`). That's a built-in GitHub Projects workflow
(`Item added to project`), not something this script does — see the
`cmd_status` comment in `.mise/tasks/gh-project` for how fragile those
built-in workflows are (an option-list rewrite silently disables them).

## The status ladder is the pipeline

`Backlog` (not scheduled) → `Needs design` (scheduled, open forks — the
`/swarmify` inbox) → `Ready` (a drone can take it) → `In progress` → `In review`
→ `Done`.

The design gate: a forked issue sits in `needs-design` → `/swarmify #n` (settle
forks *with the user*, write acceptance, split hubs into file-disjoint children)
→ `status <n> ready` → `swarm`/`warp` executes.

**A drone never touches a non-`Ready` issue.** `Ready` *is* the swarm queue —
there is no `swarmable` label (retired 2026-08-02: a second source of truth for
what the status already said, and it rotted both ways). Standing hub queue:
issue **#261**.

## `Ready` and `Needs design` are prioritised by milestone

What to pull first is the **current GitHub milestone** — `mise gh-project --
roadmap` lists open / ready / needs-design per milestone, and the owner names
the live one. `Ready` is a superset, not the queue: anything in it *could* be
taken; being in the live milestone means it *should*. Same for `Needs design` —
that column means "forks are open", not "work on this next".

There is deliberately no prose priority file. `docs/FOCUS.md` held that role and
was rewritten twice (2026-08-18, 2026-08-31) for the same rot — per-issue prose
is irresistible to append to and invisible to prune; at its worst it referenced
134 issues, 89 closed, 81 of those still reading as live. It was retired
2026-09-21 in favour of the milestone, which the board keeps live. A sentence
about an issue goes **on** the issue.

## Roadmap + hygiene

`mise gh-project -- roadmap` prints milestone swim-lanes with epic progress;
`milestone|target|start|estimate <n> [val]` set roadmap fields; `label <n>
add|rm <name>` flips a label. `hygiene [--json]` reports board invariant
violations and fixes nothing — run it whenever you look at the board.

The headline invariant used to be *"`Backlog` means no live parent"* — retired
2026-09-15 with the hub rules below: it policed a hub's status as hand-set
intent, and a derived status carries none. A child's status is its own; the
hub's is a summary of the children.

## Hubs: a parent never carries work

**Owner call, 2026-09-15** (option A of three, after the mix of "hub that is
also a bug" and "hub that is only a container" kept tripping agents, `hygiene`
and the owner alike — see the #729/#901 session):

1. **A parent never carries work.** If swarmify splits an issue, *all* of its
   work moves into children — including the defect the hub itself describes,
   which becomes "child 0: the original problem". The hub keeps the problem
   statement, the decisions, and the DAG; never an acceptance spec of its own.
2. **A child is work *required* for the parent to be done.** Anything optional
   or "may follow later" is a **sibling** that links back to the origin, not a
   child — trailing children are why hubs sat open forever.
3. **A hub's status is derived, never hand-set.** From its children, by
   `.mise/tasks/lib/hub_derive.jq` (`mise run gh-project-selftest` pins it):
   all closed → `Done` + closed · every open child `In review` → `In review` ·
   any child `Ready`/`In progress`/`In review` → `In progress` · children only
   `Backlog`/`Needs design` → left alone (filing state stays yours). Derivation
   follows the children up *or back* — a reopened child or a new `Ready` sibling
   takes an `In review` hub back to `In progress`. `--fix` is a single pass, so
   a nested hub (a child that is itself a hub) settles across two runs.
4. **A hub is never `Ready`.** `Ready` is the swarm queue; a container there
   gets pulled by a drone with nothing to do. Derivation moves it to
   `In progress`.

Who runs it: `mise run land --closes <n>` calls `gh-project sync-parent <n>`
after moving the child to `in-review`, so the hub follows the moment its last
child lands. **The push gap:** `Closes #n` fires on *push*, so hub → `Done` +
closed happens at the next `mise gh-project -- hygiene --fix` — the swarm
train gate runs it right after the push. `hygiene` reports drift as
`hub_drift`; `--fix --dry-run` previews. A hub with an *open* child missing
from the board is never derived (`unboarded_child`) — `add` the child first.

If a hub with every child closed still has unshipped scope, the fix is a new
child, not keeping the hub open by hand. The old `hollow_hub` exemption for "a
`Ready` parent with its own scope" (#240) is retired with this.

## Sub-issues

The repo uses the parent/sub-issue model. File a child under its epic with `gh
issue create --parent <parent-number> …` (gh ≥ 2.9x) — this nests it, distinct
from a `Closes #` trailer.

**Re-parenting an issue that already exists is `--parent`, NOT `--add-parent`**
(gh 2.98). The `--add-*` prefix is right for every *other* relation
(`--add-blocked-by`, `--add-blocking`, `--add-sub-issue`, `--add-label`), so the
symmetry is a trap: an issue has one parent, hence a setter. `--add-parent`
exits 1 with `unknown flag`, which a `| tail -1` in a loop swallows silently —
so a batch that looks like it parented ten children may have parented none.
Either check the exit code per call, or verify after with
`gh api graphql … issue(number:N){subIssues(first:20){nodes{number}}}`.

**`gh issue view --json blockedBy` returns an OBJECT, not an array.** The shape
is `{"blockedBy":{"nodes":[…],"totalCount":N}}`, so the jq path is
`.blockedBy.nodes[].number` — `.blockedBy[]` yields nothing and reads exactly
like "the relation was never created". There is no `blockedByIssues` field on
the GraphQL `Issue` type either; `--json blockedBy` is the supported route.

**`mise gh-project -- blocked-by <n> [<blocker>|clear]` / `blocking <n>`**
(#598) read or set native issue dependencies — read from `gh issue view --json
blockedBy`/`blocking` as above, write via `gh issue edit --add-blocked-by
<blocker>` / `--remove-blocked-by <blocker>` (both take issue **numbers**
directly and error loudly — non-zero exit, a real "could not resolve" message
— on a bad one). `clear` removes every current blocker in a loop.

**The trap this sidesteps:** the *raw* REST resource
(`repos/<repo>/issues/<n>/dependencies/blocked_by`, `POST`/`DELETE`) takes an
`issue_id` — the API's internal ~10-digit id, **not** the issue number — so a
number passed there silently succeeds against an unrelated issue or fails
opaquely with no "no such issue" error (verified 2026-08-26 setting #349
blocked-by #597 by resolving `.id` first). `gh issue edit --add-blocked-by`
(gh ≥ 2.98, this repo's pinned version) is the higher-level route and takes
plain issue numbers — **use it, not the raw API**, and the trap doesn't apply.

## Reading an issue is two `gh` calls

**RTFC — read the fucking comments.** When working an issue, read its comments,
not just the body: they often hold the actual decisions, pointers, new
direction, or bug reports that outweigh the original body.

**`gh issue view <n>` prints the body; `--comments` prints ONLY the comments**
(gh 2.97) — so reading an issue is *two* calls. `--comments` on an issue with
none gives empty output and exit 0, which is not a broken pager. `mise.toml`
exports `GH_PAGER=cat` repo-wide, so `gh` never pages even under a pty; reaching
for `--json` to dodge a suspected hang just makes you guess at field names.

## Never pass `gh --body "..."` with backticks

The shell runs command substitution and silently deletes the span, publishing
mangled text with no error. Write a heredoc to the scratchpad and use
`--body-file`.

## Never write a closing keyword in a commit body, even quoted

GitHub's parser scans the whole commit message for `close/closes/closed/fix/…
#NNN` and does not read quotation marks, negation, or context. On 2026-08-28,
`429e6e1` — a docs commit whose body recorded that a *dead* `"close #470 against
this"` instruction was **neutralized** — closed #470 the second it was pushed,
with acceptance 1 unmet and nobody's decision behind it.

So when writing *about* such an instruction, split the keyword from the number
("the `close` #NNN instruction"), or write "issue 470". Same care in issue
comments and PR bodies.

## Attribute owner decisions to the owner, verbatim

Nearly every issue body and comment here was written by an agent, so when you
write up a fork the owner settled, quote their words and label it an owner call
(`**Owner call 2026-08-21:** "…"`). Never launder it into your own reasoning.

**Why:** agents resolve contradictions by authority — an owner call outranks a
later comment, which outranks a maintained doc, which outranks an agent-written
body. A decision written up as an agent's own conclusion re-enters the record at
the *bottom* of that ladder, so the next agent is free to argue with it and the
record degrades into competing confident opinions. Attribution is what makes a
decision stick.

**How to apply:** quote the owner; date it; say what it supersedes if it
reverses something. When you hit a contradiction you cannot resolve by that
ladder, ask the owner — don't pick a side, and don't write a new comment
arguing with an old one.

## Close and reopen beats leaving an issue open forever

Owner, 2026-08-31: *"imo i'd rather close and reopen an issue than keep them
open forever and confuse agents."* An issue open across many swarms accumulates
stale paths (#614's file table pointed at `ui/menu/`, deleted in the #579
cutover), superseded decisions, and children that landed under different
assumptions; a reader cannot tell which parts still hold, and a long-open hub
keeps its milestone showing `In progress` after the work shipped. Refile the
residue as a fresh issue derived against current `master`, close the old one
pointing at it.
