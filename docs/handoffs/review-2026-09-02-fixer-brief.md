# Fixer brief — 2026-09-02 architecture review

You are one of six FIXERS landing the findings of a read-only architecture review. You work in
your own git worktree (already created for you — `pwd` to see it; it is a branch off `master`).
Read CLAUDE.md first. Your findings list is in your prompt; the reviewer already verified each
with file:line, but **re-read the code before editing** — a finding may have shifted a few lines.

## Ground rules

- **Never call an `advisor` tool. Never spawn Opus agents.** `Explore` agents only, with `model: "haiku"`.
- Cheap ladder only: `mise run check` (~20s) → `mise run test:one -- res://test/unit/<script>.gd`
  → `mise run test:dir -- res://test/unit/<dir>/`. Run the full `mise run test` **at most once**,
  at the very end, right before you report — and only if you changed non-doc code. If your
  worktree reports "Could not find type X" or a suspiciously low test count, run
  `mise run refresh` once (stale class cache), never debug it.
- **Commit as you go**, one commit per finding, staging explicit paths (`git add <path>`), never
  `git add -A`. Conventional subject (`fix(scope): …`, `docs(scope): …`, `refactor(scope): …`),
  body says which review finding it closes. End every commit message with
  `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- If a `.gd` you add/move needs a `.uid` sidecar, `mise run refresh` generates it — commit it too.
- Match the surrounding style: comment density, naming, docstrings. A doc fix rewrites the claim
  against the code as it IS; it does not add a "(updated 2026-09-02)" trail.
- When a finding says "file an issue", use `gh issue create --label <l> --body-file <tmp>`
  (never `--body` with backticks — the shell eats them). Attribute owner decisions verbatim,
  dated, as an owner call. Then `mise gh-project -- add <n>` and `mise gh-project -- status <n> backlog`.
- A finding you judge WRONG after reading the code: skip it and say why in your report. A finding
  that turns out bigger than its estimate (S/M): do the smallest correct version, file the rest.
- Do not touch files outside your unit's scope unless the finding names them. Other fixers own
  the other subsystems in parallel worktrees; the lead merges.

## Report (final message, ≤400 words)

```
branch: <name>   head: <sha>   commits: <n>
Landed: F1 ✓ (sha) …
Skipped: F? — <why>
Filed: #<n> <title> …
Tests: <what you ran + verdict; full-suite line if you ran it>
Merge notes: <anything the lead must know — files also touched by another unit, a rename other units cite>
```
