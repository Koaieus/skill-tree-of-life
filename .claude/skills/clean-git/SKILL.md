---
name: clean-git
description: 'Tidy the shared git checkout without touching anyone else''s work — sync master fast-forward only (a conflicted regenerated file like the balance snapshot is taken from upstream only when it is identical to it), go over the dirty files one by one and classify each (regenerated, editor churn, this session''s change, another agent''s live work), commit this session''s changes in groups by explicit path, merge a PR through its gate (checks green, no conflicts, ADR number free, squash, delete branch). Use when the user says "pull git", "resolve the conflict", "clean git", "let''s go over the dirty git files", "what''s dirty", "commit that stuff", "make !<n> merge", "merge PR #<n>".'
---

# clean-git

Charter (the why): `docs/charters/clean-git.md`.

Three chores — **sync**, **triage the dirty tree**, **merge a PR**. Run them
inline, no subagent. Touch nothing that is not this session's.

## Every chore starts here

1. Look before acting:
   - `git -C <checkout> status --porcelain`
   - `git -C <checkout> fetch`

   Every git call is path-pinned with `-C <checkout>`
   (`docs/domain/git-gotchas.md` → *Always `git -C <path>`*).
2. Never `git checkout master`, never `git stash` in the main checkout.

## Classify each dirty file

Diff each dirty file and put it in exactly one class:

| class | what you do |
|---|---|
| *regenerated output* | the regenerated-file test below |
| *editor churn* (no semantic change: `.import` lines, whitespace, reordered keys) | restore it — only after its diff was read and shows no semantic change |
| *this session's change* | commit it (below) |
| *another agent's live work* | leave it untouched and report it — never `checkout --`, `restore`, `add` or stash it |

A dirty file is someone else's until its diff shows otherwise. Decide per
file; never sweep.

## Regenerated-file test

For a file a task rewrites (`tools/balance/snapshot.md`, from `mise run
balance`) that is dirty or named in `pull`'s refusal:

- `git -C <checkout> diff <upstream> -- <path>` is empty → take upstream.
- non-empty → it is a real change: regenerate it with its task. Never
  hand-merge it.

## Chore: sync

1. On `master`: `git -C <checkout> pull --ff-only`.
2. Never pull into a checkout whose dirty files overlap the incoming change.
3. A refusal: resolve it with the regenerated-file test where it applies;
   surface anything else to the owner. Never a merge commit, never `--force`.

## Chore: triage the dirty tree and commit

1. Classify every dirty file (above).
2. Commit this session's changes in groups, one commit per coherent group:
   `git -C <checkout> add <path>` per file — never `-A`.
3. On the owner's machine, commit to `master`. A cloud session commits to its
   branch and opens a PR.
4. To set work aside, make a WIP commit — never bare `git stash`.
5. No push unless asked. When asked, push an explicit sha
   (`docs/domain/git-gotchas.md` → *`git push origin master` publishes
   everyone's landings*).

## Chore: merge a PR

1. Gate — all three must hold:
   - checks green;
   - no conflicts;
   - any number the branch allocated (an ADR's `NNNN`) is still free on
     `master`.
2. `gh pr merge <n> --squash --delete-branch`.
3. Then sync (above), only if the checkout is clean or its dirty files do not
   overlap the merged change.
4. A local branch is never merged this way: hand it to `mise run land`; do not
   re-implement it.

## Report

One line per file or action:

- committed — sha and paths;
- discarded — the empty upstream diff, or the read churn diff;
- merged — the PR;
- left alone — the file and whose work it looks like.
