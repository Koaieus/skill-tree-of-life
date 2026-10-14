---
name: triage
description: Empty the board's `Intake` lane with the owner — background Sonnet scouts read four issues at a time while the owner answers one AskUserQuestion per batch (close, Backlog, Needs design, rarely Ready, plus retags), and a background clerk applies each answer with a dated comment. Routing only, never design. Use when the user says "triage", "intake", "go through Intake", "route the inbox", or asks what is waiting on them on the board. Needs the owner present.
---

# Triage — route the `Intake` lane

Design and laws: `docs/charters/triage.md`. You route issues; you never
design them, and you read no issue yourself — the scouts do.

**No owner in the conversation → stop** and say triage needs them.

## 1. Snapshot

`mise run --quiet gh-project -- list intake --json`. Order: P0 → P4, then
unprioritised; oldest first within each. Cut it into batches of four. This
list is the whole run — issues filed meanwhile wait for the next one.

## 2. Keep two batches scouting

Dispatch batches 1 and 2 at once, each as
`Agent(subagent_type: "Explore", model: "sonnet", run_in_background: true)`
with this brief and the four numbers:

> Triage scout, read-only. For each issue: `gh issue view <n> --comments`
> (repo Koaieus/skill-tree-of-life), then a light look at the code or docs
> it names — enough to judge, never a design. Report per issue, at most
> eight lines:
> - **why / what:** why it was filed and what it fixes or adds (two lines)
> - **cost:** a size (xs–xl) and what it touches
> - **downside:** any UX/DX downgrade, risk or churn; `none` is fine
> - **still holds?** yes / already fixed (sha or file) / duplicate of #n / superseded
> - **specced?** does the body already carry a drone-ready acceptance spec
> - **route:** close | backlog | needs-design | ready, plus any label,
>   priority (p0–p3) or milestone change, with a one-line reason

Then end your turn; a scout's return wakes you.

## 3. Ask a batch the moment it is back

One `AskUserQuestion` per batch, one question per issue:

- **question:** `#<n> <title>` and the scout's why/what, cost and downside
  in two or three short lines, ending `Route it?`.
- **header:** `#<n>`.
- **options:** the scout's route first, marked `(Recommended)`, then the
  other routes that apply — `Close (not doing)`, `Backlog`, `Needs design`.
  Offer `Ready` only when the scout says small **and** specced. An issue
  that no longer holds offers `Close (fixed)` / `Close (duplicate #m)` first.
  Each option's description names the metadata it applies (labels, priority,
  milestone).

## 4. On each answer

In this order, so the owner never waits:

1. **Dispatch the next scout**, if any batch is unscouted.
2. **Closes are yours**, one call each (the clerk never closes):
   `gh issue close <n> --reason "not planned"|completed --comment "Triage
   (owner, <YYYY-MM-DD>): <their answer and notes, verbatim>"` — a
   duplicate is `not planned` with `duplicate of #m` in the comment.
3. **The rest goes to a clerk**: per routed issue, write the same one-line
   comment to its own scratchpad file, then a work order — post that file as
   a comment; the labels, priority and milestone to set; the status last (a
   `Ready` route names its milestone) — and
   `Agent(subagent_type: "clerk", run_in_background: true, prompt: "<order path>")`.
4. **Ask the next batch** if its scout is back; otherwise end your turn.

## 5. Close out

When the snapshot is empty and every clerk has reported: `mise gh-project
-- hygiene`, then the session report (`docs/domain/session-report.md`) with
a `Routed` table (`# · route · note`) in place of `Landed`, and anything the
owner deferred under `Needs the owner`.
