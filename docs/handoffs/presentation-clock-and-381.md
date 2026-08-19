# Handoff: presentation-clock entity gap (#485) + hit/heal unification (#381)

Written 2026-08-19 against master @ `7e8dcda`. Authoritative homes are #485 and
#381 themselves (both carry the full design context as of this commit) — this
file exists only to record the *relationship* between the two dispatches and
answer whether they can run in parallel.

## What each session should read first

- **Session A — #485** (`gh issue view 485 --comments`): entity-level wounds
  and death currently reveal at raw model-mutation time, not on the VFX
  arrival clock. Full root cause, design decisions, and a 5-step suggested
  order are in the issue body. Start there.
- **Session B — #381** (`gh issue view 381 --comments`): collapse
  `AttackOutcome.hits`/`heals` into one polymorphic `Array[HitInstance]`.
  Read the sequencing comment added 2026-08-19 before starting.

## Can they run in parallel?

**Not cleanly on separate worktrees started at the same time.** Both touch
`systems/battle_system.gd`'s `_apply_outcome()` and `_flush_presentation()`,
and both touch the VFX coordinators' `_show_presentation` — not a textual
overlap you can `git merge` past, a **control-flow** overlap: #485 adds a
manifest-recording pass through the hit/heal loops, #381 replaces those loops'
shape entirely (two lists → one).

**Verdict: sequential. #485 first, #381 second.**

Reasoning (from an advisor consult during the design discussion): #381 does
not reduce the complexity of #485's work — the cascade wound/HP-chip/death
data #485 needs to attribute lives entirely *outside* `AttackOutcome.hits`/
`heals` (it's computed reactively off `Events.skill_node_depleted`, recorded
nowhere), so unifying hits+heals touches none of #485's actual bug. #485's
manifest should be designed to consume `(reveal_key, effect)` entries
agnostic to whether the source was one list or two — once that's true, #381
becomes a pure builder simplification that can land without touching #485's
player logic again.

If you must parallelize anyway (e.g. two people, both sessions already
launched): give #381 a hard rule to leave `_apply_outcome`'s hit/heal-loop
*shape* alone and land only the `DamageInstance`/`HealingInstance` →
`HitInstance` data-type change + call-site updates, deferring the loop
collapse until after #485 merges. Whoever lands second rebases regardless.

## Live facts worth having in hand (already in the issues, repeated here for speed)

- `.claude/rules/multiplayer-sync.md`: commands carry `stable_id`, never a
  node/entity reference. `DamageInstance.target` / `HealingInstance.target`
  are object refs today — settle whether the collapsed `HitInstance` needs to
  become wire-shaped as part of #381's target shape decision.
- #474 (closed, locked): world mutation must stay synchronous, VFX stays a
  pure observer. Neither #485 nor #381 may move mutation back inside a VFX
  await — only the *reveal* of already-applied state may defer.
- A real, scoped, independently-fixable bug found while investigating #485:
  `AllocationSystem._on_entity_died`'s death-strip never populates
  `AllocationVFX._cascade_scheduled`, so an entity's whole territory shatters
  in one unstaggered frame. This is #485's step 2 — reuse the existing
  `BattleSystem._cascade_layers` stagger.

## Delete condition

Delete this file once both #485 and #381 are closed. If #485 closes first,
update this file's verdict section only if #381's approach changed from what
the sequencing comment on #381 assumes — otherwise no update needed, just wait
for #381 to close too.
