---
name: triage
description: 'Empty the board''s `Intake` lane with the owner — background Sonnet scouts read four issues at a time while the owner answers rapid-fire AskUserQuestion calls, up to four verdicts per call, each carrying what the issue wants, what is in code and the proposed verdict (close, Backlog, Needs design, rarely Ready, plus retags), and a background clerk applies each answer with a dated comment. Routing only, never design. Use when the user says "triage", "intake", "go through Intake", "route the inbox", or asks what is waiting on them on the board. Needs the owner present.'
---

# Triage

Empty the board's `Intake` lane with the owner, one routing call per issue:
close, `Backlog`, `Needs design`, or (rarely) `Ready`, plus any retag. Triage
decides where an issue goes, never how it is built — an open fork goes to
`Needs design` with the owner's note. Charter: `docs/charters/triage.md`.

## 0. Owner present, or stop

If the owner is not here to answer (a headless session), stop and say:
triage routes out of `Intake` only with the owner present.

## 1. Snapshot the queue, once

1. `mise run --quiet gh-project -- list intake --json` — this is the whole run.
   Keep the tool's order (P0 → P4, then unprioritised; oldest first within a
   priority); re-sort nothing. An issue filed after this waits for the next run.
2. One GraphQL call over the snapshot's numbers, one alias per issue:

   ```
   gh api graphql -f query='{repository(owner:"Koaieus",name:"skill-tree-of-life"){i<n>:issue(number:<n>){subIssues(first:50){nodes{number state}}} i<m>:issue(number:<m>){subIssues(first:50){nodes{number state}}} …}}'
   ```

3. An issue with sub-issues is a **hub**: drop it from the queue. Its open
   children that are in the snapshot take its place, each tagged `child of #h`.
   A child in any other lane is not touched. A hub is never asked, routed or
   closed by triage.
4. Cut the queue, in order, into batches of four.

You read no issue yourself; your context is the scout reports and the answers.

## 2. Pipeline, two deep

- **Start:** dispatch scouts for batches 1 and 2 in the background (one
  message, two `Agent` calls).
- **A report is back and no question is up** → ask it (step 4). Two back at
  once → the lower batch number first.
- **After each answer**, one turn: in one message, two `Agent` calls —
  dispatch the scout for the next unscouted batch, and spawn this batch's
  clerk (step 5). No scratch file before either. Then ask the next batch that
  is back; if none is, end the turn.
- A scout that fails, or leaves an issue unjudged → re-dispatch once for
  exactly those numbers. A second failure → those issues stay in `Intake`,
  listed under `Not done`. Never judge them yourself.

## 3. The scout

`Agent`, `subagent_type: "Explore"`, `model: "sonnet"`, background,
read-only. Brief:

> Light triage scout, read-only. For each of these issues: <#n, #n (child of
> #h), …>, read the issue and look at the code just enough to judge it.
> Report per issue, at most eight lines:
> - **Wants:** why it exists and what it fixes or adds (its ask, from the body).
> - **Cost:** a size, and what it touches.
> - **Downside:** any UX/DX downgrade or risk.
> - **In code:** what is there now against that ask — absent / partly there
>   (file) / already fixed (sha) / duplicate of #n / superseded.
> - **Spec:** whether the body carries a drone-ready acceptance spec, and
>   whether it carries a `drift-stamp` block.
> - **Filer set:** the `Intended lane:` line, milestone, priority (as given,
>   or none).
> - **Route:** one of Close (not planned) / Close (fixed) / Close
>   (duplicate #m) / Backlog / Needs design / Ready, with a one-line reason,
>   plus any label/priority/milestone change.
> No design, no acceptance spec, no argument. Report every issue named.

## 4. Ask the batch — `AskUserQuestion`, always

Every owner call goes through `AskUserQuestion`: one call per batch, one
question per issue (at most four), built from the scout's report alone.
Never a prose list, never "reply with issue numbers", never "which next?".

Per question:
- header `#<n>` (twelve characters at most); the question text ends in `?`;
  a child's question names its hub (`child of #h`).
- the question serves: **what the issue wants**, **what is in the code** now,
  the cost and any downside.
- two to four options; the scout's route first, marked recommended, its
  description carrying the scout's one-line reason; every other option's
  description names what it would apply.
- the tool supplies `Other` itself; never add one.
- the options: `Close (not planned)`, `Backlog`, `Needs design`, and `Ready`
  only when the scout found it small, fully specced, carrying a `drift-stamp`,
  and with a milestone set or proposed. If the issue no longer holds, offer
  `Close (fixed)` or `Close (duplicate #m)` *instead of* `Close (not planned)`,
  never beside it.

Reading the tool's *Other*:
- **names a route** (with riders: retags, priority, milestone, a note,
  "actually a duplicate of #m") → that route, riders applied.
- **asks something** → answer in prose from the scout's report, then re-ask
  that issue alone in a one-question `AskUserQuestion` call.
- **defers** ("later", "skip") → the issue stays in `Intake`, gets no clerk
  order, and goes under `Needs the owner`.
- design thoughts in any answer → route `Needs design` with the text quoted;
  do not pursue them.

## 5. Apply — one background clerk per answered batch

`Agent`, `subagent_type: "clerk"`, background; the plain-prose work order is
the whole spawn prompt. You write no files and run no board write yourself.

Per issue, in this order:
1. `comment "Triage (owner, <YYYY-MM-DD>): <answer and notes>"` — the owner's
   answer verbatim, with the date.
2. labels, priority, milestone as the answer set them.
3. the status or the close:
   - `Backlog` → `status backlog`
   - `Needs design` → `status needs-design`
   - `Ready` → `status ready` with its `milestone m` (the clerk checks the
     drift stamp first)
   - `Close (not planned)` → `close as not planned`
   - `Close (fixed)` → `close as completed`
   - `Close (duplicate #m)` → `close as duplicate of #m`

These closes are manual — no commit backs them, so no `Closes #n` footer
applies; the clerk closes exactly what the order names.

Read every clerk report. A `FAILED` or `SKIPPED` line → re-order it once in a
new clerk; a second failure → `Not done`. Exception: a `Ready` line that
`FAILED` for no drift stamp is not re-ordered — list it under `Not done` as
*no drift stamp — `/swarmify` or `/spec` it*.

## 6. End the run

The run ends when every snapshotted issue is routed, deferred or failed, and
every clerk has reported. Not when `Intake` is empty.

1. Spawn one last background clerk with the order `hygiene --fix` (it moves
   an `Intake` hub whose children reached `Ready` or beyond) and read its report.
2. Session report, as `docs/domain/session-report.md` shapes it, every
   section present even when `none`, with **Routed** in place of **Landed**:

   ```
   **Routed**
   | # | route | note |
   |---|---|---|
   ```

   - `Not done` — scout failures, clerk failures, no-drift-stamp `Ready`s.
   - `Needs the owner` — deferrals, and each hub still in `Intake` because
     every child went to a parked lane: *children routed, derivation does not
     move it*.
