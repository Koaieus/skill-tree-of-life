# Dormant Cores

A **Dormant Core** is an entity that holds a small patch of territory and never
moves or acts. It has no initiative, no vision, and no AI; it exists to deny that
territory until someone kills it, and to pay out when they do. Mechanically it is a
real `Entity` (`entity/blocker/blocker_entity.tscn`) so damage, the allocation
gate, death cleanup, and loot are all existing systems rather than a special
case.

## Two names, and which one goes where

| | name | where |
|---|---|---|
| player-facing | **Dormant Core** | `Entity.display_name`, tooltips, design docs, anything a player reads |
| internal | **blocker** | every code identifier — `BlockerSize`, `spawn_blocker`, `blocker.tres`, `blocker_per_*`, the `Blocker_*` node names |

`blocker` self-describes the *mechanic*, so the code keeps it; nothing a player
sees uses it. Code identifiers are not renamed: renaming an `@export` var makes
Godot drop the old key from any saved resource and silently fall back to the
default, which would change level generation in every authored config.

## Who shoots at one

A Dormant Core is `targeted_by_ai = false` on its `Faction`, so `AiRecon` drops
its nodes from every NPC target list. That filter is deliberately NOT:

- **the attitude relation.** A blocker stays `HOSTILE` to everyone, which is what
  lets the *player* clear one and makes the forced-dealloc cascade and XP gating
  treat a cleared blocker as a real kill. Moving the filter into
  `Entity.attitude_to` would disarm the player too.
- **absolute.** It is the NPC's *default stance*, re-evaluated every turn.

The exception is being **growth-capped**: an NPC with no unowned node adjacent
to its territory has nowhere left to allocate. `AIController` asks
`AiRecon.is_growth_capped()` once per turn and sets `Entity.ai_growth_capped`;
`AiRecon.is_ai_target()` reads it and unlocks — for that turn only — the cores the
attacker's `EntityNavigator.borders(node)`. Kill, relic, expand. Why the unlock is
bordering rather than global is
[ADR 0008](../adr/0008-a-growth-capped-npc-breaks-out-through-a-bordering-door.md).

Five load-bearing details:

| detail | why |
|---|---|
| asked **after** the growth step | "nowhere left to allocate" is a fact about the post-growth board, not a guess about the pre-growth one |
| **topological only** — never "can I afford it" | an entity banking SP with nowhere to spend it is precisely the case this must answer *yes* for |
| unlock only what **borders** the attacker | capped-by-allies has no door at all; an unreachable core is not what is capping you |
| **both** consumers of `is_ai_target` unlock | the target list AND `AiCombatScorer.expected_damage`'s per-hit filter; unlocking only the list enumerates candidates that score 0 EV, so the AI would attack only cores it could one-shot |
| always **assigned**, never only set | the stance must not outlive the turn that earned it, or an NPC that broke out once keeps shooting scenery |

Growth then runs a **second** pass after the attack loop, so the freed node is
allocated on the same turn as the kill — and allocating it is what claims the
relic (NPCs auto-pick each loot round, see `SkillDustAddon`).

### Unlocking is not enough — the door has to win

A capped NPC that also sees a real hostile scores both on raw EV, so a distant
enemy would win and the wall beside it never gets hit. `AiCombatScorer` therefore
carries a **breakout bonus**: while `ai_growth_capped`, any target the attacker's
navigator `borders(...)` scores `_BREAKOUT_WEIGHT` (500) — the same predicate the
unlock uses. Depleting a node force-deallocates it, so a bordering node is a door,
and nothing about that is blocker-specific. It is ungated by `ai_tier`, sits above
the tier terms (so a capped NPC is door-first at every tier; tier preferences still
decide *among* doors, which all carry +500) and below `_KILL_BONUS` on a non-door
target. The rejected shapes are in
[ADR 0008](../adr/0008-a-growth-capped-npc-breaks-out-through-a-bordering-door.md).

## The footprint, and the falloff that shapes it

`GraphProcgen` rolls a **bonus-node footprint** per placement and
`EntityFactory.spawn_blocker` force-allocates it alongside the core. Ranges are
authored per size on `GraphProcgenBlockers` (`footprint_small_min` … ), default
**small 0-2, medium 2-4, large 4-6**; size reads on the board as territory.

**The footprint is grown, not sampled.** From the core, the pass repeatedly picks a
random eligible node adjacent to what the blocker already holds. That makes it
**connected by construction**, which two things depend on:

- the falloff below measures hops over the blocker's OWN subgraph, so a node
  reachable only through someone else's territory would take no falloff at all;
- the max hop is bounded by the rolled count, which is the whole clamp (below).

Eligibility is the placement pass's own filter plus a claim set: never a starter
core, never a keystone, never inside a starter's `blocker_min_hops_from_core` ball
(**the safety radius covers the whole footprint, not just the core**), and never a
node another Dormant Core already holds. Short of candidates, a blocker **shrinks
its footprint**; the blocker count and the tier ladder never shrink.

There is no connectivity guard: a footprint may sit on a cut vertex and wall off a
pocket. The kill-strip is the door.

### The falloff

Every Dormant Core carries `effects/blocker_footprint_falloff.tres`, one shared
`AuraEffect`: `reach: null`, `scope: OWNED`, `metric: HopMetric`,
`distance_scale: ProportionalScale(per_unit = 1.0)`, one modifier
`node_health ADD_BASE -5`.

**It arrives through the ordinary `CoreClass.effects` seam, not a `grant_effect`
call.** `blocker_entity.tscn` authors `core_class = entity/blocker/blocker_core.tres`,
and `Entity._ready` applies it on `add_child`, so `spawn_blocker` contains no line
about the aura. That class is a Dormant Core's *composition*, never a pick: it
carries no modifiers, no sigil and no turn hook, sets `pickable_in = 0`, is absent
from `core_class_roster.tres`, and is filed under `entity/blocker/` so
`CoreClass.load_all()` cannot enumerate it. An owned node caps at **the size's
CON-derived `node_health` baseline minus 5 per hop from the core**, and
`ProportionalScale` puts the source itself at scale 0 — the core keeps its full
authored HP.

**Not a scaled `SET`.** `distance_scale` multiplies the modifier's *value*, so
`SET X` scaled by `s(h)` yields `X · s(h)`; getting `X − 5h` out of that needs
`s(h) = 1 − 5h/X`, i.e. the scale would have to know X, coupling the two knobs
`AuraEffect` deliberately keeps orthogonal. The additive spelling also composes
with every other `node_health` source instead of bypassing them.

**The footprint range IS the clamp.** `node_health` has no floor, and nothing
stops `-5/hop` going negative past hop `X/5` — except that a footprint of `n`
nodes reaches at most hop `n`. At the authored ranges the worst cases are a
large at hop 6 (80 − 30 = 50) and a small at hop 2 (20 − 10 = 10). Raising a
`footprint_*_max` past `node_health / 5` is what would need a stat minimum.

Because the class carries it, the aura is present on **every** blocker,
footprint or not: on a lone core it is inert (the only node in scope is the
source, at scale 0). That unconditional presence is also what makes the peer
rebuild idempotent.

### Density

A footprint roughly triples a Dormant Core's board share. The `GraphProcgenBlockers`
class defaults (`procgen/modules/blockers.gd`: `blocker_per_small/medium/large`
**30/50/100**, ~20.5% of an 800-node map owned) and the lobby's **"Regular"** rung
(`ui/frontmatter/lobby_options/blocker_options.tres`) agree, so a direct sandbox
launch and normal lobby play are the same game. A rung that cannot be placed
degrades into "every eligible node is a blocker".

### Multiplayer: nothing new on the wire

A joining peer runs no procgen. Ownership of every footprint node crosses as
`GraphSnapshot`'s per-node `owner_id`, the core as `EntitySnapshot`'s
`core_location`, and the aura as an ordinary entity-wide effect row whose re-grant is
idempotent. `spawn_snapshot_entity` spawns with an EMPTY footprint — and the caps
still land, because assigning `Entity.core_location` dispatches `_on_core_moved`, a
full aura recompute over the world the graph half just decoded. The peer grants the
aura from its own authored scene rather than depending on the wire interning the
effect's resource path.

## Sizes, boards, and loot tiers

Three sizes (`EntityFactory.BlockerSize`), each with an authored stat board (which
sets the held node's HP) and an authored **loot book** — a `SpellBook` whose spells
the killer's relic can offer. Blockers never cast; the book is purely what they
carry.

| size | book | N |
|---|---|---|
| SMALL | bruiser, healing_beam | 2 |
| MEDIUM | leafblower, resonator, trail_blazer | 3 |
| LARGE | reverberator, cyclone | 2 |

The books are `entity/blocker/blocker_spellbook_{small,medium,large}.tres`. The
tiers are a **loot-rarity** axis, deliberately decoupled from `SpellDef.min_degree`
(a cast-time gate). Tiers are not monotonic in payout: N is the whiff dial (below),
and a spell may appear in more than one tier, which raises both tiers' payout rate.
Weights *within* a tier do not exist; if wanted, promote the books from `SpellBook` to
a dedicated loot-table resource.

`spark` and `lightning_bolt` are in no book — `spellbook_default.tres` makes them
innate for every entity, and `SkillDustAddon._exclude_permanently_known` drops innate
spells from an offer, so listing one would be a dead entry that still inflated the
book size. `test/unit/entity/test_spellbook_prune.gd` asserts both that rule and that
every authored spell is in some book or explicitly excluded.

## The loot-book prune

A relic's claimant picks exactly **one** spell from whatever is offered, so the only
lever on how fast spells spread is **how often a kill offers nothing**. That is what
the prune is for — not narrowing the choice, which `_exclude_permanently_known`
already does.

At spawn, each Dormant Core copies its tier book and pops random spells off the copy
until a roll fails (`SpellBook.duplicate_pruned`). With `n` spells left, it pops with
probability `n / (n + m)`:

```
E[kept]      = n * m / (m + 1)
P(kept == 0) = 1 / C(n + m, n)        # integer m
```

`m = 1` is the special case where every outcome in `{0..n}` is **equally likely**,
and `P(empty) = 1/(n+1)`: book size is the whiff dial — 50% for N=1, 33% for N=2, 25%
for N=3, 20% for N=4.

**`m` is tuned DOWN to slow spell spread, never up.** Raising it keeps more spells, so
kills offer nothing *less* often — at n=4, P(empty) falls from 20% (m=1) to 2.9%
(m=3). The knob is `GraphProcgenBlockers.blocker_spell_prune_m`, range 0.5–3.0,
default 1.0.

The roll is **seeded per placement** by procgen, off the same derived stream as
blocker placement, so it is a replay input. A joining client runs no procgen: the kept
spells cross **by value**, as indices into the interned spell table on the entity
snapshot row (`network/entity_snapshot.gd` `_encode_spell_ids`). Never roll the prune
unseeded at spawn. See `.claude/rules/multiplayer-sync.md`.

## The look

A Dormant Core's core node wears a **null-field blob**, not a rock (#1526): a
tar-black goo whose edge deforms very slowly (it is dormant), with drifting texture
layers inside and a scanline-tear / channel-jitter glitch.

- **Tier = fused lobe count**, never node size: `BlockerVisual.tier_lobes`
  (`[1, 2, 3]`, small / medium / large). `SkillNode.radius` already grows with stake,
  so size-per-tier would make a staked small core outgrow an unstaked medium one. The
  tier is latched with the owner's instance id, so a later write or a freed corpse
  never changes the look.
- **Damage** keeps the three crack stages (intact / cracked ≤ 2/3 / shattered ≤ 1/3
  HP, thresholds in GDScript). As the stage rises the lobes drift apart with goo
  strands between them, cracks bite the edge, and the bleed light grows.
- **Variants**: `BlockerVisual.seed_for(stable_id)` drives texture offset, lobe phase
  and glitch timing — deterministic, so every peer draws the same blob.
- **Rendering**: one shared `skill_node/visuals/blocker_blob_material.tres` for every
  core; `lobes` / `seed` / `damage` are instance uniforms, and the material is bound
  only while the visual is visible (a cleared or sensed core claims no slot). Motion
  runs on `TIME` in `blocker_blob.gdshader` — zero per-frame CPU. The bleed colour is
  `Emissive.tint(bleed_base, bleed_tier)`, written once onto the shared material.
- **Interior layers** are plain `sampler2D` slots (`layer_a`, `layer_b`) read as
  luminance masks and tinted in-shader: swapping a slot's texture on the `.tres`
  needs no code change. Tuning lives on the material (`deform_speed`,
  `glitch_intensity`, `damage_spread`, tints, scrolls) — open it in the inspector.
- **Territory colour** is a void indigo, `Color(0.30, 0.27, 0.42)`, on
  `blocker_entity.tscn` (what the territory tint reads) and `factions/blocker.tres`.
