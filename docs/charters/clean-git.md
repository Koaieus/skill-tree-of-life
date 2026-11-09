# Clean-git — charter

The design behind `.claude/skills/clean-git/SKILL.md`. The file is derived
from this; change the wish here, then re-derive. See [README](README.md) for
the protocol. Owner, 2026-11-10: *"yeah a tiny skill like clean-git sounds
good. tiny charter, tiny skill"*.

## What clean-git is for

Three git chores the owner asks for in a few words, which sessions kept
re-deriving from scratch: **sync** ("pull git, resolve conflicc"), **triage
the dirty tree** ("go over dirty git files and see what we do with each"),
and **merge a PR** ("make !1744 merge"). Nothing else.

## The cost model

The chores are a dozen commands, run inline, no subagent. The expensive
thing is **another session's unstaged work in the shared checkout**, which
is unrecoverable: one wrong `checkout --` or bare `stash` costs a peer
hours. Every law is about not touching what is not yours.

## Laws

1. **Look before acting.** `git -C <checkout> status --porcelain` and
   `git -C <checkout> fetch` first; every git call path-pinned with `-C`
   (`docs/domain/git-gotchas.md` → *Always `git -C <path>`*). *Why:* the
   checkout is shared, and the cwd is not reliably the one you think.
2. **A dirty file is someone else's until shown otherwise.** Diff each
   dirty file and put it in one class: *regenerated output* (law 3),
   *editor churn* (no semantic change), *this session's change*, or
   *another agent's live work*. Churn is restored only once its diff was
   read and shows no semantic change (`.import` lines, whitespace,
   reordered keys). Another agent's work is left untouched and reported —
   never `checkout --`, `restore`, `add` or stash. *Why:* a shared checkout
   holds peers' uncommitted work (2c31bb1a), and the owner's "what do we do
   with each" is a per-file call, not a sweep.
3. **A regenerated file is discarded only when it equals upstream.** A
   file a task rewrites (`tools/balance/snapshot.md`, from `mise run
   balance`) that is dirty, or named in `pull`'s refusal: `git -C <checkout> diff
   <upstream> -- <path>` empty → take upstream; non-empty → it is a real
   change, regenerate it with its task, never hand-merge it. *Why:* the
   one conflict seen was such a file, byte-identical to upstream
   (2ef23c76); the explicit test keeps "it's just generated" from
   discarding a real balance change.
4. **Sync is fast-forward only.** `git -C <checkout> pull --ff-only` on
   `master`; a refusal is resolved by law 3 where it applies, and anything
   else is surfaced to the owner — never a merge commit, never `--force`,
   and never a pull into a checkout whose dirty files overlap the incoming
   change. *Why:* trunk-based history, and a pull that rewrites a peer's
   dirty file is law 2 broken by a side door (08faeccf).
5. **Commit in groups, by explicit path, without pushing.** Owner's
   standing rules: commit as you go, trunk-based; `git add <path>` per
   file, never `-A`; one commit per coherent group; on the owner's machine
   commit to `master`, a cloud session commits to its branch and opens a
   PR. To set work aside, a WIP commit — never bare `git stash` (the stash
   stack is shared across worktrees). No push unless asked; then push an
   explicit sha (`git-gotchas.md` → *`git push origin master` publishes
   everyone's landings*). *Why:* the owner's standing calls, given a repo
   home so the skill does not hang on one session's memory.
6. **A PR merges only through its gate.** Checks green, no conflicts, and
   any number a branch allocated (an ADR's `NNNN`) still free on `master`;
   then `gh pr merge <n> --squash --delete-branch`, the house squash
   precedent (`docs/domain/cloud-automerge.md`). Then law 4, only if the
   checkout is clean or the dirty files do not overlap. A local branch is
   never merged this way — it goes through `mise run land`. *Why:* two
   branches can claim the same ADR number and both be green (08faeccf);
   and a local branch landed by hand skips `land`'s rebase-and-test.
7. **The report is one line per file or action.** What was committed
   (sha, paths), discarded (law 3's empty diff, or law 2's churn), merged, and what was
   left alone and whose it looks like. *Why:* the owner asked "what do we
   do with each" — the left-alone lines are the answer they read.

## Foreign laws

- [warp](warp.md) law 9 — a local branch lands by `mise run land`;
  clean-git never re-implements it (law 6).
- [warp](warp.md) law 10 — never `git checkout master`, never `git stash`
  in the main checkout; clean-git's laws 4–5 keep the same line.

## Frontmatter

- `name: clean-git`
- `description: 'Tidy the shared git checkout without touching anyone
  else''s work — sync master fast-forward only (a conflicted regenerated
  file like the balance snapshot is taken from upstream only when it is
  identical to it), go over the dirty files one by one and classify each
  (regenerated, editor churn, this session''s change, another agent''s
  live work), commit this session''s changes in groups by explicit path,
  merge a PR through its gate (checks green, no conflicts, ADR number
  free, squash, delete branch). Use when the user says "pull git",
  "resolve the conflict", "clean git", "let''s go over the dirty git
  files", "what''s dirty", "commit that stuff", "make !<n> merge", "merge
  PR #<n>".'` — one line in the file.

## What the skill file must not contain

Session ids, dates, the owner's quotes, the reasons behind each law, the
text of `git-gotchas.md` (it points there). It carries the three chores as
steps, the four file classes, and the report shape.

## Revisit when

- A second regenerated file shows up as a false conflict — the fix moves
  to tooling (`.gitattributes` `merge=ours`, or `land` regenerating the
  snapshot), and law 3 shrinks to a pointer.
- `mise run land` grows a PR mode — law 6 becomes a pointer to it.

## Incident corpus

| date | source | finding | laws |
|---|---|---|---|
| 2026-11-04 | `docs/corpus/2026-11-09-skill-candidates-c.md`, session 2ef23c76 | "pull git, resolve conflicc": the conflict was `tools/balance/snapshot.md`, identical to upstream; local discarded, fast-forwarded | 3, 4 |
| 2026-11-05 | same, session 2c31bb1a | "go over dirty git files and see what we do with each": diff, classify (churn / real / another agent's), verify, commit in groups, no push | 2, 5, 7 |
| 2026-11-04 | same, session 08faeccf | "make !1744 merge": gate green, no conflicts, ADR numbers free on master, squash, delete branch, no pull into the dirty shared checkout | 4, 6 |
