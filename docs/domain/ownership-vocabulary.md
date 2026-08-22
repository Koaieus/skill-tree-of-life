# Ownership vocabulary

Every question of the form *"may X do this to node N?"* is one question with one
answer: `SkillNode.ownership_bit(viewer)`. It returns exactly one bit describing
N's relation to `viewer`, delegating to `Entity.attitude_to` for the
owned-by-someone-else case.

```gdscript
enum Ownership { NEUTRAL = 1, MINE = 2, ALLY = 4, HOSTILE = 8 }
```

`Entity.attitude_to` is the single home of the player/enemy relation (#384);
`ownership_bit` is the node-side accessor over it. Neither is cached — a node
cannot store "I am hostile", because hostile *to whom*.

## The rule

**Never write `node.owned_by == entity` (or `!=`) to ask an ownership
question.** Ask for the bit and test it:

```gdscript
# wrong — "not mine" is not "hostile"
if node.owned_by != attacker:
    damage(node)

# right
if node.ownership_bit(attacker) & SkillNode.Ownership.HOSTILE:
    damage(node)
```

`owned_by == entity` is only correct when you literally mean *this one entity's
own nodes* and nobody else's — the navigator's mirror contents, the allocation
system's per-entity gates, "which of MY nodes did this blade select". Those are
identity questions, not relation questions, and they stay as they are.

The tell is the word in the comment. If it says *enemy*, *hostile*, *friendly*,
*ally*, or *theirs*, the code must not say `owned_by ==`.

## Why this keeps breaking

The identity form was correct for the whole life of the codebase before factions
existed (#384, 2026-08-07): with two entities and no camps, "not me" and "my
enemy" were the same set. #384 introduced `Faction` and migrated the consumers it
found, but every site it missed kept compiling, kept passing its tests, and kept
being subtly wrong in a way that only shows up once a board has **three or more
parties** — an ally, or a third camp.

That is why the failures all arrived at once, months later, when hot-seat coop
(#459) and the blocker camp (#460) put a third party on the board on the same
day. Nothing regressed; the latent bugs simply became reachable.

Fixed in that pass:

| Site | Was | Meant |
|---|---|---|
| `MeleeAttackPlan.collect_target_excludes` | `sn.owned_by == attacker` | `MINE\|ALLY` — a blade swept a partner's territory |
| `OwnerFilter.Scope.ENEMY` | `to.owned_by != caster` | `HOSTILE` — chains hopped into a partner's nodes |
| `AiCombatScorer.expected_damage` | summed every hit | only hits the AI should value (see below) |

Already correct, because #384 migrated them: `RangedAttackPlan` (at both
target-validate and land time) and `NodeTargeting`.

## The flag vocabulary is shared, deliberately

Two `@export_flags` surfaces let a designer pick a bucket set in the inspector:

- `NodeTargeting.ownership_filter` — who a spell/attack may be **aimed at**.
- `OwnerFilter.ownership_filter` — who a spell may **chain into** during
  propagation.

They take the **same flag set**, including the composites: `Friendly` (6) is
`MINE|ALLY`, `Allocated` (14) is any owned node, `Any` is 15. Keep them in step.
`OwnerFilter` used to carry its own `Scope` enum instead; it could not express
"me *and* my camp" at all, and its `ENEMY`/`ALLY` members meant `!= caster` /
`== caster` — identity wearing a relation's name.

Note `ALLY` (4) alone is the camp **without** the caster's own nodes. That is
kept reachable on purpose ("buff every ally but yourself"); a heal almost always
wants `Friendly` (6). And `HOSTILE` (8) excludes `NEUTRAL` — unallocated ground
is not hostile, so a spell meant to chain through empty ground needs
`Hostile|Neutral` (9).

Godot cannot take a `const` in an `@export_flags` annotation, so the hint string
is duplicated between the two. The *semantics* are not duplicated — both resolve
through `ownership_bit`, and that is the part that must never fork.

## Attitude is not the only gate

A relation answers *may I*, not *should I*. `Faction.targeted_by_ai` — should an
NPC brain spend AP on this camp? — deliberately sits beside `attitude_to` rather
than inside it. It is false only on `blocker.tres`.

("Does this camp's survival decide the run?" used to be its sibling
`counts_for_victory`. It left `Faction` entirely in #517 because it needed a
per-*entity* answer: it is now a `ContestantRule` the victory condition owns,
reading a `scenery` group off the entity's scene. See
`docs/domain/victory-system.md`.)

Neither belongs in `attitude_to`: a
dormant core must stay `HOSTILE` so the **player** can clear it, and so damage,
the forced-dealloc cascade and XP gating treat that as a real kill. `targeted_by_ai`
is filtered in `AiRecon.is_ai_target`, which is the single predicate both the AI's
target *list* and its EV *sum* go through — filtering only the list would leave
an AoE banking value for scenery it clipped, and the AI would still steer into it.

See [victory-system.md](victory-system.md) for why those two flags are kept
separate from each other.

## Checklist for a new ownership gate

1. Call `ownership_bit(viewer)`; test the bit. Never compare `owned_by`.
2. Decide whether `NEUTRAL` belongs in your set — it is the bucket people forget.
3. If a designer should be able to retune it, expose the same `@export_flags`
   set, not a bespoke enum.
4. Give it a fixture with **three** parties (self, ally, hostile). A two-entity
   fixture cannot distinguish identity from relation, which is exactly how this
   class of bug survived: two spell/melee fixtures called an entity "defender"
   while handing it the attacker's own default faction, and passed anyway.
