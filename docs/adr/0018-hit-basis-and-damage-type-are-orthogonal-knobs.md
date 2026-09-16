---
id: 0018
title: A hit's amount basis (flat vs % of max HP) and its mitigation class are orthogonal knobs, authored explicitly — no derived coupling, for now
status: accepted
date: 2026-09-16
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "attack/outcome/hit_instance.gd"
  - "attack/outcome/damage_instance.gd"
  - "attack/formulas/mitigation.gd"
  - "attack/spell/on_hit/damage_effect.gd"
  - "effects/status/poison.gd"
  - "docs/domain/attack-timeline.md"
tags: [combat, attacks, damage, mitigation, architecture, design]
---

# ADR 0018 — A hit's amount basis and its mitigation class are orthogonal knobs, authored explicitly

## Context

A hit carries two independent-looking questions. **How big is the number:**
`HitInstance.basis`, `AmountBasis { FLAT, PERCENT_MAX }` — HP, or a fraction of
the target's max HP, resolved once in `land_on` by `HitInstance.resolve_amount`
ahead of `CritRoll.apply` and ahead of `Mitigation`. **Does armour apply:**
`DamageInstance.type`, `PHYSICAL | MAGIC | TRUE`, where `TRUE` bypasses
`Mitigation.apply`. So a `PERCENT_MAX` hit is sized against the target first and
then mitigated like any flat hit — unless its type is `TRUE`.

`PoisonStatus`, the first `PERCENT_MAX` producer, pairs it with `TRUE`. That
raised the question: is the pairing one producer's choice, or a rule the engine
should enforce — `PERCENT_MAX ⇒ unmitigated`, on the intuition that "a share of
your health" shouldn't be diluted by flat armour? And with `POISON` a candidate
future damage type, should types map onto a `mitigation × basis` spec at all?

## Decision

**`basis` and `type` stay independently authored. Nothing derives one from the
other.** `DamageEffect` exports both; `HealEffect` exports `basis` (no mitigation
axis); `PoisonStatus` exports `basis` and mints `TRUE` as a property of what
poison is, not as a consequence of choosing `PERCENT_MAX`.

Owner, 2026-09-16: *"only if we could distill hard gameplay rules like 'poison
always unmitigated' or '%dmg always unmitigated' we could set hard mappings, and
i don't think i would want to commit to those rules (yet? tho maybe `%dmg ×
mitigation:true` feels a bit off in virtually any game), then orthogonal
authoring would remain the best. if we start adding tons of sources for minting
different damages which should broadly follow defaults, option 3 we should keep
in mind"*

**A for-now call with a named revisit trigger** — see alternative (3).

## Consequences

- Every new damage producer sets both knobs itself. Forgetting one is silent —
  a `PERCENT_MAX` hit armour eats when the author meant `TRUE` — so both exports
  say so in their docstrings, and the `.tres` shows both values plainly.
- `PERCENT_MAX + MAGIC` (a %-bolt armour reduces) and `PERCENT_MAX + TRUE`
  (poison) are both representable with no special case. That expressiveness is
  the point; flat armour against a small pool's % damage is a tuning matter, the
  owner's to tune.
- No table, no `Type.AUTO`, no mitigation-spec resource exists. Do not hand-roll
  a second coupling mechanism ad hoc; when the trigger fires, build (3).

## Alternatives considered

### (B) Per-basis subclasses — `PercentMaxDamageInstance` / `PercentMaxHealInstance`
**Rejected.** Two classes for one value, and it cannot compose with the existing
`BladeDamageInstance` / `RangedHitInstance` subclasses without multiplying the
hierarchy. `basis` is a field on the base for the same reason `is_crit` is.

### (2) Couple them — `PERCENT_MAX ⇒ TRUE`
**Rejected for now.** A hidden derived rule behind what reads as an independent
flag; it dies at the first %-bleed armour *should* reduce; and it is a
damage-only rule on a knob heals share.

### (3) A basis→default-type table with explicit override
A `Type.AUTO` tri-state, or a mitigation-spec `Resource` that damage types map
onto (natural if `POISON` becomes a damage type). **Not rejected — deferred.**
No default is distillable yet, so a table would only relocate today's authoring
burden into speculative infrastructure. **Revisit trigger:** the owner commits
to a hard rule, or a third-plus producer is copy-pasting the same `basis`/`type`
pairing as boilerplate.
