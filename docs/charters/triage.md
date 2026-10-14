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
   stops and says so.
2. **Snapshot once, priority first.** The queue is `list intake --json`
   taken at the start, ordered P0 → P4 then unprioritised, oldest first
   within a priority. Issues filed during the run wait for the next run, so
   the run ends.
3. **Two-deep pipeline.** Dispatch two scouts (batches 1 and 2) in the
   background at the start. When a batch's report arrives and no question is
   pending, ask it. After each answer: dispatch the next scout first, then
   hand the answers to the clerk, then ask the next ready batch. The owner
   never waits on a scout the lead could have started earlier.
4. **The scout's report is short and decision-shaped.** Per issue: why it
   exists and what it fixes or adds (two lines), the cost (a size, and what
   it touches), any UX/DX downgrade or risk, whether it still holds (already
   fixed, a duplicate of #n, superseded), and a recommended route plus any
   label/priority/milestone change. No design, no acceptance spec.
5. **One question per issue, the recommendation first.** Options are the
   routes that apply: close as not planned, `Backlog`, `Needs design`, and
   `Ready` only when the scout found the issue small and fully specced (a
   `Ready` issue WILL be pulled by the next swarm). Already-fixed or
   duplicate → close as completed/duplicate is offered first. The owner's
   free-text "Other" and notes carry retags and riders.
6. **Every routing leaves its reason on the issue.** The clerk posts a
   one-line comment quoting the owner's answer verbatim with the date, then
   sets status, labels, priority and milestone, or closes. A routing with no
   comment is a decision that lives only in this transcript.
7. **Mechanics are the clerk's, except a close.** One background Haiku
   `clerk` per answered batch, given a plain-prose work order; the lead
   runs no other board write inline while a question could be up. The
   clerk never closes an issue (its own law), so a close is the lead's one
   `gh issue close --comment` call — cheap enough not to stall the next
   question. `Ready` needs a milestone
   (hygiene's `unmilestoned_ready`): the lead's order names one.
8. **The run ends on an empty snapshot**, with `gh-project hygiene` and the
   session report (`docs/domain/session-report.md`): a `Routed` table (#,
   route, note), `Needs the owner` for anything the owner deferred.

## What the skill file must not contain

The owner's quotes, the reasoning behind the pipeline depth or batch size,
dates, incidents. It carries the steps and the scout brief.

## Revisit when

- Scouts routinely return after the owner has answered — the pipeline
  should go three deep or batches should shrink.
- The owner keeps overriding the scout's recommended route on one kind of
  issue — that kind wants a rule in the scout brief.
- `Intake` routinely holds more than ~30 issues at a run's start — filers
  are skipping the fix-before-filing rung (`session-report.md`), which is
  the bug to chase, not triage throughput.

## Incident corpus

| date | source | finding | laws |
|---|---|---|---|
| 2026-10-14 | `docs/corpus/2026-10-14-followup-issues-at-session-end.md` | 37 of 43 session-end follow-ups were small known fixes; 38% of the issues they produced were still waiting in `Backlog`/`Needs design`, and one flake was filed four times. The lane and the skill were born from it | all |
