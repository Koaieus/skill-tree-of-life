---
name: triage
description: Empty the board's `Intake` lane with the owner — background Sonnet scouts read four issues at a time while the owner answers one AskUserQuestion per batch (close, Backlog, Needs design, rarely Ready, plus retags), and a background clerk applies each answer with a dated comment. Routing only, never design. Use when the user says "triage", "intake", "go through Intake", "route the inbox", or asks what is waiting on them on the board. Needs the owner present.
---

# Triage — route the `Intake` lane

Design and laws: `docs/charters/triage.md`. You route issues; you never
design them, and you read no issue yourself — the scouts do.

**No owner in the conversation → stop** and say triage needs them.

## 1. Snapshot

`mise run --quiet gh-project -- list intake --json`, taken once. It is
already ordered P0 → P4 then unprioritised, oldest first; keep that order
and cut it into batches of four. This list is the whole run — an issue
filed meanwhile waits for the next one.

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
> - **filer set:** the body's `Intended lane:` line, milestone, priority
>   (`—` for each not set); `hub` if the issue has sub-issues
> - **route:** close (not planned | fixed | duplicate #n) | backlog |
>   needs-design | ready, plus any label, priority (p0–p4) or milestone
>   change, with a one-line reason

Then end your turn; a scout's return wakes you. A scout that fails or
leaves an issue unjudged is re-dispatched once with exactly those numbers;
if that fails too, those issues stay in `Intake` and go under `Not done`
— never judge them yourself.

## 3. Ask a batch the moment it is back

Two back at once → the lower batch number first. One `AskUserQuestion` per
batch, one question per issue, within the tool's limits (at most four
questions per call, two to four options per question, a header of at most
twelve characters, every question ending in `?`):

- **question:** `#<n> <title>` and the scout's why/what, cost and downside
  in two or three short lines, ending `Route it?`.
- **header:** `#<n>`, nothing more.
- **options, at most four:** the scout's route first, marked
  `(Recommended)`, then the other routes that apply — `Close (not planned)`,
  `Backlog`, `Needs design`. Offer `Ready` only when the scout says small
  **and** specced **and** a milestone is set or proposed. An issue that no
  longer holds offers `Close (fixed)` or `Close (duplicate #m)` *instead of*
  `Close (not planned)`. A hub is not routed: offer only close or leave.
  Each option's description names the metadata it applies (labels,
  priority, milestone). The tool supplies `Other` itself; never add one.

Read an `Other` answer three ways: it names a route (with riders — retags,
priority, milestone, a note, "duplicate of #m") → that route, riders
applied; it asks something → answer in prose from the scout's report and
re-ask that one issue in a one-question call; it defers ("later", "skip")
→ the issue stays in `Intake`, gets no clerk order, and lands under `Needs
the owner`. Design thoughts in an answer go to `Needs design` with the text
quoted — never pursue them.

## 4. On each answer

In this order:

1. **Dispatch the next scout**, if any batch is unscouted.
2. **Closes are yours** (the clerk never closes), two calls each: write
   `Triage (owner, <YYYY-MM-DD>): <their answer and notes, verbatim>` to a
   scratchpad file, `gh issue comment <n> --body-file <file>`, then
   `gh issue close <n> --reason "not planned"` | `--reason completed` |
   `--reason duplicate --duplicate-of <m>`. These are manual closes: no
   `Closes #n` footer.
3. **The rest goes to a clerk**: per routed issue, the same one-line
   comment in its own scratchpad file, then a work order — post that file
   as a comment; the labels, priority and milestone to set; the status last
   (a `Ready` line names its milestone) — and
   `Agent(subagent_type: "clerk", run_in_background: true, prompt: "<order path>")`.
   When a clerk reports, re-order any `FAILED`/`SKIPPED` line once; a
   second failure goes under `Not done`.
4. **Ask the next batch** if its scout is back; otherwise end your turn.

## 5. Close out

When every snapshotted issue is routed, deferred or failed and every clerk
has reported: `mise gh-project -- hygiene`, then the session report
(`docs/domain/session-report.md`), every section present: a `Routed`
table (`# · route · note`) in place of `Landed`, scout and clerk failures
under `Not done`, deferrals under `Needs the owner`.
