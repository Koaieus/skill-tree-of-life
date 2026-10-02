# Issue tracking & the project board

The full version of `CLAUDE.md` → *Issue tracking*. Read this before running
`mise gh-project`, filing an issue, swarmifying, or dispatching a drone.

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`). `gh label list` is
the label set; `blocked` means an open upstream fork.

**Milestone or label?** A milestone is a *push that closes* — one per issue, and
it is the pull order (below). A label is *area or kind* — any number, never
closes (`ai`, `ui`, `frontmatter`, `tech-debt`). The test: if you would ever
close it, it is a milestone. An area with no end is a label, so a `Backlog`
issue with no push behind it carries **no milestone** rather than a catch-all
one; from `Needs design` on it is scheduled and carries its push.

## The board

`mise gh-project -- list|add|status|priority|size`. `list
[backlog|needs-design|ready|in-progress|in-review|done|all]` shows a column —
that's how an agent finds work to pick up; add `--json` (with `mise run
--quiet`) for machine-readable output. See `.mise/tasks/gh-project`.

**A new issue joins the board by itself** — every issue filed in the repo is
auto-added to the project and lands in `Backlog`. Never `gh-project add` a
fresh issue (owner, 2026-10-02: *"any issue filed here does NEVER have to be
manually `gh-project add`ed"*); call `status` only for a different lane
(e.g. `needs-design` or `ready`). `add` remains for an issue that somehow
isn't on the board (`unboarded_child`). Both are built-in GitHub Projects
workflows (auto-add, `Item added to project`), not something this script does — see the
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
An open hub whose open children are *all* parked in `Backlog`/`Needs design`
(none `Ready`, `In progress` or `In review`) is `stalled_hub` — nobody is
actually working it; `--fix` never touches it, since detaching a child is an
owner call. The lead's move is to set the stalled hub itself to `Needs design`
— owner, 2026-10-01: "moe hubs with parked kids to needs design; a swarmify
sesh may pick em up by proxy, or such session may backlog it".

`Ready` with no milestone is a hygiene flag, not a hold: owner, 2026-10-01,
"Ready = ready = pick it up."

A unit that lands with open owner questions goes back to `Needs design`, its
landed code kept: owner, 2026-10-01, "questions? -> back to needs design (keep
the landed stuff, swarmify would set out a final course no problem)". `land
--closes` already wrote `Closes #n`, so after the push reopen it and set the
status — then re-read its state: GitHub can process the push's close *after*
an immediate reopen, closing it again.

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
(#598) read or set native issue dependencies through the REST resource
`repos/<repo>/issues/<n>/dependencies/blocked_by` — REST so the links still
land when the GraphQL hour is spent (see Rate limits below; 2026-10-01 the
clerk's `gh issue edit --add-blocked-by` calls all died on the quota and the
same links went through REST first try). `clear` removes every current
blocker. Setting an existing link is a no-op.

**The trap it holds:** that resource's `issue_id` is the API's internal
~10-digit id, **not** the issue number — a number passed there silently
succeeds against an unrelated issue or fails opaquely (verified 2026-08-26
setting #349 blocked-by #597 by resolving `.id` first). The script's
`issue_db_id` is the one place that resolves it and errors on a number that is
not an issue. **Never call the raw resource by hand — call the script.**
`gh issue edit --add-blocked-by <number>` also works, but rides GraphQL.

## Reading an issue is two `gh` calls

**RTFC — read the fucking comments.** When working an issue, read its comments,
not just the body: they often hold the actual decisions, pointers, new
direction, or bug reports that outweigh the original body.

**`gh issue view <n>` prints the body; `--comments` prints ONLY the comments**
(gh 2.97) — so reading an issue is *two* calls. `--comments` on an issue with
none gives empty output and exit 0, which is not a broken pager. `mise.toml`
exports `GH_PAGER=cat` repo-wide, so `gh` never pages even under a pty; reaching
for `--json` to dodge a suspected hang just makes you guess at field names.

## Rate limits: the GraphQL hour is shared, and REST misreports it

Every `gh issue …` and `gh project …` command is GraphQL, drawing on one
5000-point hour shared by every session on the account. GraphQL bills by the
*requested* connection size, so one careless query can cost hundreds: a single
`gh project item-list` on this board measured **~607 points** (2026-10-01), and
`gh-project status <n>` used to run one per read. A clerk verifying six issues
spent most of the hour, and every agent's `gh` then failed with "API rate limit
already exceeded for user ID …" — the **primary** (hourly) limit. `gh-project`
now reads the board with hand-written queries (~6 points the whole board, ~1 an
issue); its header holds the cost model. **Never call `gh project item-list`.**

**Read the counter from GraphQL itself**:
`gh api graphql -f query='{rateLimit{used remaining resetAt}}'`. REST
`gh api rate_limit` reported graphql `used: 5` at the moment GraphQL reported
1315 — which is how an earlier pass misdiagnosed exhaustion as the burst limit.

GitHub's two limits read differently and want opposite responses:

- **Primary** — "API rate limit [already] exceeded". Lasts until `resetAt`, up
  to an hour; sleeping and re-running only spend turns. REST (`gh api repos/…`)
  is a separate 5000/h pool and still works: `gh-project blocked-by` is REST,
  `status` writes fall back to REST on their own.
- **Secondary** — "You have exceeded a secondary rate limit" (or HTTP 429).
  Per-minute limits that no `rate_limit` endpoint reports — roughly 100
  concurrent requests, ~2000 GraphQL points/min (~900 for REST), ~80
  content-creating requests/min and 500/h (creates, comments, edits — a
  clerk pass's shape), ~90 s server CPU per minute. Clears within minutes as
  the traffic eases. Four concurrent 607-point board reads alone used to cross
  the per-minute point cap.

`.mise/bin/gh` retries the secondary limit (15 s × attempt, 4 attempts, under
the 120 s tool timeout), never retries the primary, and on giving up prints
which one it was and what still works. It sits first on PATH via `mise.toml`,
so it covers `mise run` tasks always, but a session's own shell only when the
process that spawned it (`claude remote-control`, a terminal) was started after
the change — a daemon started earlier keeps its old PATH until relaunched.
`GH_SHIM=off` bypasses it; `GH_SHIM_RETRIES` / `GH_SHIM_BACKOFF` tune it.

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
