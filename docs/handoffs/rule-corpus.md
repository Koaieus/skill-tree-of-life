# Rule corpus — restructure landed, harness half unbuilt

**Written against `9400d48`.** Authoritative homes: `.claude/rules/writing-rules.md`
(doctrine), `docs/domain/breadcrules.md` (tiering), issues **#363** and **#364**.
This file only points.

> **Ribbon cut 2026-08-03** — reflection done and reported; findings filed as a
> comment on **#364** (uncounted `CLAUDE.md` always-on payload; unrouted
> `godot-workflow.md` sections). Don't redo it. Deletion still gated on #364.

## First task: cut the ribbon — you are the first agent running the new corpus

You booted on a rewritten rule corpus. Nobody has yet observed it from the
outside, and the agent that wrote it (2026-08-03) is the one least able to judge
it — that's precisely the bias `writing-rules.md` now warns about. So before
picking up work, **spend one turn reflecting and report to the user**:

1. **Did the tiering hold?** The always-on tier should be **8 breadcrules,
   ~2.6k bytes** — no rule bodies. Confirm with `mise run rules-hygiene`.
2. **Did the scoped rules fire when they should?** Opening a `.tscn` should pull
   `godot-scene-authoring`; something under `graph/`, `systems/`, `attack/`,
   `effects/` or `procgen/` should pull `graph.md`. Extension globs were verified
   by probe on 2026-08-03 — confirm they still resolve for you.
3. **Do the crumbs make you want to follow them?** This is the judgement only a
   fresh agent can make. For each of the 8: does it tell you *when* you'd need
   the doc, or only what the doc is about? A crumb naming a topic instead of a
   failure mode is a **crumb bug** — fix the trigger wording, don't grow the doc.
4. **Is anything now under-served?** `godot-workflow.md` went 17.9k → ~500B. If
   you find yourself hitting a Godot gotcha the crumb didn't warn you about, that
   is the highest-value finding available right now — record it.
5. **Is the tone calibrated?** `963618e` found an overstated warning was costing
   agents turns (stalling, workarounds, `md5sum` ceremony). Flag anything that
   reads as alarm rather than instruction.

Report honestly, including "it reads fine". A confirmation from a cold context is
worth more than the author's confidence.

## State

Landed 2026-08-03, `113cc88`..`9400d48` (12 commits):

- Always-on tier **28,549 B → 2,674 B**; every always-on rule is now a breadcrule.
- `mise run rules-hygiene` — reports tier violations, fixes nothing. **Dead-glob
  detection** is the headline: a `paths:` matching zero files silently never loads.
- `mise run refresh` — editor pass + a verdict, so nobody hand-diffs churn.
- Eviction + calibration doctrine in `writing-rules.md`; extension globs verified.
- `swarm`/`drone`: workers now make their own `mise` worktrees as teammates
  (task board + mailbox come back). Dispatch is **two-step** — a named teammate
  ignores the spawn prompt and idles until `SendMessage`.

## Open, ordered

1. **#364 — harness hooks** (Stop + UserPromptSubmit context band). Unbuilt; the
   design is fully written in the issue. This is the half that makes the corpus
   work self-sustaining rather than a one-off cleanup.
2. **#363 — demote `stats-system.md` (53k) and `skill-node-visuals.md` (46k).**
   Both **scoped**, so they cost nothing until triggered — do this
   *opportunistically*, in a session already working those files. Not a standalone
   pull ahead of a FOCUS lane.

Neither is scheduled. `docs/FOCUS.md` still wins over anything here.

## Live numbers

- Always-on: **2,674 B / 4,000 B budget**, 8 rules.
- Corpus total ~145k B — fine; only the always-on slice is paid by everyone.
- `rules-hygiene` green except the two #363 entries. That's the expected baseline —
  **anything else is new**.

## Delete this file when

#364 lands and the ribbon-cutting reflection above has been reported once.
#363 does not gate deletion — it lives on its issue.
