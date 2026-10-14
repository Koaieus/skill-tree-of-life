# Triage — charter

The design behind `.claude/skills/triage/SKILL.md`. The file is derived from
this; change the wish here, then re-derive. See [README](README.md) for the
protocol.

## What triage is for

Empty the board's `Intake` lane with the owner, one routing call per issue.
`Intake` is where every new issue lands and where every filing made without
the owner stays (`docs/domain/issue-workflow.md` → *Filing*), so it is the
owner's inbox and nobody else routes out of it. Owner, 2026-10-14:

> *"an intake/triage run skill that allows agents to sit with me basically
> AskUserQuestion for each one, small introduction of why the issue and
> what it fixes or adds, potential costs or UX/DX downgrades. No need to go
> really deep because the swarmify session gets to the nitty gritty while
> the triage is more 'do we close as not doing, or move backlog, or move
> needs Design (or outright ready in some rare cases of small or perfectly
> specced issues). And maybe retag it and or update other metadata. That's
> the whole skill."*

Triage is not swarmify. It decides *where an issue goes*, never *how it is
built*: a fork stays open and goes to `Needs design` with the owner's note.

## The cost model

**The owner's wall-clock is the expensive thing; scouting must hide behind
it.** The owner, same message: *"say there are 12 in Intake, agent triage
starts by letting 2 sonnet drones each scan 4 issues each, light explore.
Then as one finishes, AskUserQuestion. I answer them, and likely by the
time i did the other exporer is back. After i submit the turn goes back to
the agent who could send the next explorer out before asking the next set
of questions. So they work while i pick my answers. Until queue empty."*
So the run is a two-deep pipeline: one batch being answered, one being
scouted. Applying an answer (a status, a label, a close) must not stall the
next question either, so it goes to a background clerk.

**A batch is four issues** because `AskUserQuestion` takes at most four
questions: one scout, one batch, one question call.

**Sonnet scouts, read-only.** Judging cost and a UX/DX downgrade is
judgement, not a grep, so the scout is `Explore` at `model: "sonnet"` —
an explicit owner pick here, overriding CLAUDE.md's default Haiku pin for
`Explore`, which exists to stop an accidental inherited Opus. The lead
reads no issue itself; its context is the scout reports and the answers.

## Laws

1. **The owner is present, or there is no triage.** Routing out of `Intake`
   is an owner call by definition; a headless session that loads this skill
   stops and says so. *Why:* every other route out of `Intake` is a filer
   deciding for the owner, which is what the lane exists to stop.
2. **Snapshot once, in the tool's order; a hub is not a queue item.** The
   queue is `list intake --json` taken at the start; the tool already sorts
   P0 → P4 then unprioritised, lowest number (oldest) first within a
   priority, so the lead re-sorts nothing. The snapshot is the whole run: an
   issue filed meanwhile waits for the next one. Then one GraphQL call over
   the snapshot's numbers (`subIssues` per issue, aliased) finds the hubs;
   a hub leaves the queue and its open children that sit in `Intake` — they
   are already in the same list — are the units, each asked as `child of
   #h`. A child in another lane was routed already and is not touched. A
   hub is never asked, never routed and never closed by triage: its status
   is derived from its children (`issue-workflow.md` → *Hubs*; clerk law
   4 refuses a status on one), and closing its last open child closes it.
   A hub that is itself in `Intake` stays there while its children are
   routed; the close-out `hygiene --fix` (law 8) moves it once a child is
   `Ready` or beyond. Derivation leaves a hub alone when every child is
   parked (`Backlog`/`Needs design`), so such a hub is still in `Intake`
   after the run and is reported under `Needs the owner` as *children
   routed, derivation does not move it*. Owner, 2026-10-14: *"To me a hub
   just means a set of coherent or interdependent issues. Can be treated as
   stand in for the list of subissues. Of which only Intake units would
   need a treatment"*. *Why:* a live re-read mid-run re-orders the batches
   under the scouts, and a priority-first order means the owner's first
   answers are the ones that unblock work in flight; a hub in a batch is a
   scout slot and an owner question spent on something no answer can move,
   and the sub-issue lookup is a board read at snapshot time, not the issue
   reading law 3 keeps off the lead.
3. **Two-deep pipeline.** Dispatch two scouts (batches 1 and 2) in the
   background at the start. When a report is back and no question is up,
   ask it; two back at once → the lower batch number. After each answer,
   one turn: dispatch the next unscouted batch and spawn the batch's clerk
   (law 7) as two `Agent` calls in the same message; then ask the next
   batch that is back, else end the turn.
   A scout that fails, or whose report leaves an issue unjudged, is
   re-dispatched once for exactly those numbers; a second failure leaves
   them in `Intake` under `Not done`, never guessed at by the lead. *Why:*
   the owner's answer time is the slot the next scout runs in; anything the
   lead does before dispatching eats that slot — the scout and the clerk
   go out together, and no scratch file precedes either (clerk law 12). A
   failed scout is noise once and a finding twice.
4. **The scout's report is short and decision-shaped.** Per issue, at most
   eight lines: why it exists and what it fixes or adds; the cost (a size
   and what it touches); any UX/DX downgrade or risk; whether it still holds
   (already fixed, duplicate of #n, superseded); whether the body already
   carries a drone-ready acceptance spec and a `drift-stamp` block; what
   the filer set (the `Intended
   lane:` line, milestone, priority — `issue-workflow.md` → *Filing* makes
   those the filer's hand-off to triage); and a recommended route plus any
   label/priority/milestone change. No design, no acceptance spec. *Why:*
   the question is built from this report alone, and the lead reads nothing
   else; a report that argues is a question that argues; and a stamp
   noticed here keeps a stampless issue off the `Ready` menu before the
   clerk has to fail it (law 7).
5. **One question per issue, inside the tool's limits.** `AskUserQuestion`
   takes at most four questions per call (hence the batch of four), two to
   four options per question, a header of at most twelve characters
   (`#<n>`), and each question must end in a question mark; the tool adds
   its own free-text *Other*. So a question lists **at most four options**,
   the scout's route first and marked recommended: `Close (not planned)`,
   `Backlog`, `Needs design`, and `Ready` only when the scout found it small,
   fully specced, carrying a `drift-stamp` and with a milestone set or
   proposed (a `Ready` issue WILL be pulled by the next swarm; the clerk
   skips `ready` with no milestone and fails it with no stamp, law 7). An
   issue that no longer holds offers `Close (fixed)` or
   `Close (duplicate #m)` *in place of* `Close (not planned)`, never beside
   it. A hub gets no question (law 2); a child's question names its hub. *Other* is read
   three ways: it names a route (with riders: retags, priority, milestone, a
   note, "actually a duplicate of #m") → that route, riders applied; it asks
   something → answered in prose from the scout's report and the issue
   re-asked alone in a one-question call; it defers ("later", "skip") →
   the issue stays in `Intake`, gets no clerk order, and lands under `Needs
   the owner`. Design thoughts in an answer go to `Needs design` with the
   text quoted — triage never pursues them. *Why:* a fifth option or a
   thirteen-character header fails the call and costs the owner a round;
   the owner routinely answers a menu by redirecting its premise
   (swarmify's corpus), so *Other* is a path, not an error.
6. **Every routing leaves its reason on the issue.** A one-line comment
   quoting the owner's answer verbatim with the date — `Triage (owner,
   <YYYY-MM-DD>): <answer and notes>` — written in the clerk's order
   inline (the clerk files and posts it; clerk law 2), then status, labels,
   priority and milestone. A routing with no comment is a decision that
   lives only in this transcript.
7. **Every mechanic is the clerk's, closes included; the lead writes no
   files.** One background Haiku `clerk` per answered batch, its plain-prose
   work order *in the spawn prompt* — per issue: the comment text, the
   labels/priority/milestone, then the status (a `Ready` line names its
   milestone) or the close with its reason (`not planned` | `completed` |
   `duplicate of #m`). A `Ready` line is gated by the clerk on the
   issue's drift stamp, checked before the status is set (clerk law 9):
   no stamp → the line is `FAILED`, the issue stays where it is, and the
   lead lists it under `Not done` with *no drift stamp — `/swarmify` or
   `/spec` it* rather than re-ordering it. Owner, 2026-10-14: *"Yes,
   drift-check"*. No scratch file per comment, no order file: the
   lead spends one turn on the spawn (clerk law 12; owner, 2026-10-14:
   *"Clerks not closing means a more expensive model must."*). The lead
   runs no board write inline. Triage's close routes are manual by nature —
   no commit backs them, so the land task's `Closes #n` footer never
   applies; the clerk closes exactly what the order names (clerk law 4).
   The lead reads every clerk report; a `FAILED`/`SKIPPED` line is
   re-ordered once, then listed under `Not done`. *Why:* a close done by
   the lead was a Fable-priced call and a scratch file per comment was a
   Fable-priced turn, both in the slot the owner's next answer runs in;
   and a stampless issue in `Ready` is pulled by the next swarm with no
   reading list, which is the queue entering unspecced.
   (Was: closes the lead's, comments from files, 2026-10-14 morning —
   superseded the same day by the owner's clerk call above.)
8. **The run ends when every snapshotted issue is routed, deferred or
   failed and every clerk has reported.** Then `gh-project hygiene` and the
   session report (`docs/domain/session-report.md`), every section present:
   `Routed` (#, route, note) in place of `Landed`; `Not done` for scout and
   clerk failures; `Needs the owner` for deferrals. *Why:* a deferred issue
   stays in `Intake` by design, so "empty lane" is the wrong end condition;
   and a report the owner reads on a phone must say what did not happen.

## What the skill file must not contain

The owner's quotes, the reasoning behind the pipeline depth or batch size,
dates, incidents. It carries the steps and the scout brief.

## Revisit when

- Scouts routinely return after the owner has answered — the pipeline
  should go three deep or batches should shrink.
- The owner keeps overriding the scout's recommended route on one kind of
  issue — that kind wants a rule in the scout brief.
- A hub in `Intake` is left there after a run because every child routed
  to a parked lane (law 2) — `hub_derive.jq` could follow the children
  down (`Needs design` if any child is, else `Backlog`), which is the
  `stalled_hub` rule `gh-project` already states.
- `Intake` routinely holds more than ~30 issues at a run's start — filers
  are skipping the fix-before-filing rung (`session-report.md`), which is
  the bug to chase, not triage throughput.

## Incident corpus

| date | source | finding | laws |
|---|---|---|---|
| 2026-10-14 | `docs/corpus/2026-10-14-followup-issues-at-session-end.md` | 37 of 43 session-end follow-ups were small known fixes; 38% of the issues they produced were still waiting in `Backlog`/`Needs design`, and one flake was filed four times. The lane and the skill were born from it | all |
