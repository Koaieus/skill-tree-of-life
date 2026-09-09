# Dormant Cores

A **Dormant Core** is an entity that holds a small patch of territory and never
moves or acts. It has no initiative, no vision, and no AI; it exists to deny that
territory until someone kills it, and to pay out when they do. Mechanically it is a
real `Entity` (`entity/blocker/blocker_entity.tscn`) so damage, the allocation
gate, death cleanup, and loot are all existing systems rather than a special
case.

## Two names, and which one goes where (#587)

| | name | where |
|---|---|---|
| player-facing | **Dormant Core** | `Entity.display_name`, tooltips, design docs, anything a player reads |
| internal | **blocker** | every code identifier — `BlockerSize`, `spawn_blocker`, `blocker.tres`, `blocker_per_*`, the `Blocker_*` node names |

`blocker` self-describes the *mechanic* very well, so the code keeps it. It is a
poor name for the *thing*, which is why nothing a player sees uses it.

The rename was deliberately **not** applied to code identifiers. Renaming an
`@export` var makes Godot drop the old key from any saved resource and silently
fall back to the default — for `blocker_per_small` / `blocker_min_hops_from_core`
that would quietly change level generation in every authored `GraphProcgenConfig`
with nothing to catch it. Not worth it for an internal name that is already
accurate.

## Who shoots at one (#604)

A Dormant Core is `targeted_by_ai = false` on its `Faction`, so `AiRecon` drops
its nodes from every NPC target list. Two things that filter is deliberately
NOT:

- **It is not the attitude relation.** A blocker stays `HOSTILE` to everyone,
  which is what lets the *player* clear one and what makes the forced-dealloc
  cascade and XP gating treat a cleared blocker as a real kill. Moving the
  filter into `Entity.attitude_to` would silently disarm the player too.
- **It is not absolute.** It is the NPC's *default stance*, re-evaluated every
  turn.

The exception is being **growth-capped**: an NPC with no unowned node adjacent
to its territory has nowhere left to allocate. If the thing walling it in is
scenery it refuses to look at, it banks SP forever and its turn does nothing.
So `AIController` asks `AiRecon.is_growth_capped()` once per turn and sets
`Entity.ai_growth_capped` from the answer; `AiRecon.is_ai_target()` reads it
and unlocks — for that turn only — the cores that `borders_territory()`. Kill,
relic, expand.

The bordering half is not decoration: an entity capped by its own allies has
nothing to break through, and the wall — when there is one — is adjacent by
definition. A core further out only becomes reachable once a node beside it is
allocated, which a capped entity cannot do anyway. Why the unlock is bordering
rather than global, and what happens without the test, is
[ADR 0008](../adr/0008-a-growth-capped-npc-breaks-out-through-a-bordering-door.md).

Five details that are load-bearing:

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

Making a core *targetable* only fixes the case where it is the only thing in
sight. A capped NPC that also sees a real hostile scores both on raw EV, so a
distant enemy wins the tie and the wall beside it never gets hit: the same
"stuck" complaint in a different costume, and a LARGE core (high HP, no kill
bonus available) loses that comparison every turn forever.

So `AiCombatScorer` carries a **breakout bonus**: while `ai_growth_capped`, any
target that `borders_territory()` scores `_BREAKOUT_WEIGHT` — the same
predicate the unlock uses, one rule with two readers.
Depleting a node force-deallocates it, so a bordering node is a door — and
nothing about that is blocker-specific, which is the point. A capped NPC walled
in by a real camp punches through it on exactly the same reasoning.

It is ungated by `ai_tier` (like the kill bonus — being stuck is not a tactical
subtlety a naive brain is allowed to miss) and sized to sit *between* the two
things it is ordered against: above any ordinary EV difference, below
`_KILL_BONUS` on a non-door target, since a kill that is right there is still
worth taking and the next AP re-evaluates back onto the door.

It is deliberately NOT ordered against the `ai_tier` terms (cut-vertex 25/tier,
weak-point 5/tier — 75 at most): at 500 it outranks all of them, so a capped
NPC is door-first at every tier. The tier layer keeps its meaning *among* doors,
since every door carries the same +500 and cut-vertex / weak-point preference
still decides which one. Why the bonus sits above the tier terms rather than
inside them, and the four shapes this deliberately is not — a faction analysis,
a proximity filter, a global unlock, a tier-gated bonus — are
[ADR 0008](../adr/0008-a-growth-capped-npc-breaks-out-through-a-bordering-door.md).

## The footprint, and the falloff that shapes it (#777)

Until #777 a Dormant Core held exactly the node it sat on, at every size — so
size was legible only through a visual and a tooltip, and whether the thing
landed on a bunker or a spike addon was a coin flip rather than a shape.

Now `GraphProcgen` rolls a **bonus-node footprint** per placement and
`GameRoot.spawn_blocker` force-allocates it alongside the core. The ranges are
authored per size on `GraphProcgenBlockers` (`footprint_small_min` … ), default
**small 0-2, medium 2-4, large 4-6** — so a small can still roll 0 and behave
exactly like the pre-#777 blocker, and size finally reads on the board as
territory, which is the game's own vocabulary for "how much is here".

**The footprint is grown, not sampled.** From the core, the pass repeatedly
picks a random eligible node adjacent to what the blocker already holds. That
makes it **connected by construction**, which two things depend on:

- the falloff below measures hops over the blocker's OWN subgraph, so a node
  reachable only through someone else's territory would take no falloff at all;
- the max hop is bounded by the rolled count, which is the whole clamp (below).

Eligibility is the placement pass's own filter plus a claim set: never a starter
core, never a keystone, never inside a starter's `blocker_min_hops_from_core`
ball — **the safety radius covers the whole footprint, not just the core**, since
a 3-node blocker reaching into a camp's opening ball is exactly the "boxed in by
boulders" failure #300 named — and never a node another Dormant Core already
holds. Short of candidates, a blocker **shrinks its footprint**; the blocker
count and the tier ladder never shrink.

There is deliberately **no connectivity guard**. Owner call, 2026-09-07:
*"dormant cores are called 'blockers' for a reason"* — a footprint may sit on a
cut vertex and wall off a pocket. The kill-strip is the door.

### The falloff

Every Dormant Core carries `effects/blocker_footprint_falloff.tres`, one shared
`AuraEffect`: `reach: null`, `scope: OWNED`, `metric: HopMetric`,
`distance_scale: ProportionalScale(per_unit = 1.0)`, one modifier
`node_health ADD_BASE -5`. So an owned node caps at **the size's CON-derived
`node_health` baseline minus 5 per hop from the core**, and `ProportionalScale`
puts the source itself at scale 0 — the core keeps its full authored HP.

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

The aura is granted **unconditionally**, footprint or not: on a lone core it is
inert (the only node in scope is the source, at scale 0), and a grant that is
always present is what makes the peer rebuild idempotent.

### Density had to move with it

A footprint roughly triples a Dormant Core's board share, so the density that
shipped alongside one-node blockers (10/25/100) would have put **~42%** of an
800-node map under one. Both the `GraphProcgenBlockers` class defaults and the
lobby's **"Regular"** rung now read **30/50/100** — 50 blockers, ~20.5% owned —
so a direct sandbox launch and the lobby's normal play the same game. The rest
of the ladder was re-pitched against the same cost (Few 40/80/125, Lots
20/35/70, Heavy 15/25/50); the old high rungs claimed 74% and >100% of the
board once footprints landed, and a rung that cannot be placed silently
degrades into "every eligible node is a blocker".

### Multiplayer: nothing new on the wire

A joining peer runs no procgen, and needs no footprint field either. Ownership
of every footprint node crosses as `GraphSnapshot`'s per-node `owner_id`, the
core as `EntitySnapshot`'s `core_location`, and the aura as an ordinary
entity-wide effect row whose re-grant is idempotent. `spawn_snapshot_entity`
therefore spawns with an EMPTY footprint — and the caps still land, because
assigning `Entity.core_location` dispatches `_on_core_moved`, which is a full
aura recompute over the world the graph half just decoded.


## Sizes, boards, and loot tiers

Three sizes (`GameRoot.BlockerSize`), each with an authored stat board (which
sets the held node's HP) and an authored **loot book** — a `SpellBook` whose
spells the killer's relic can offer. Blockers never cast; the book is purely
what they carry.

| size | book | N |
|---|---|---|
| SMALL | bruiser, healing_beam | 2 |
| MEDIUM | leafblower, resonator, trail_blazer | 3 |
| LARGE | reverberator | 1 |

The tiers are a **loot-rarity** axis, deliberately decoupled from `SpellDef.min_degree`
(a cast-time gate). `healing_beam` is the clearest case: cheap to obtain, still
needs degree 3 to cast.

`spark` and `lightning_bolt` are in no book — `spellbook_default.tres` makes them
innate for every entity, and `SkillDustAddon._exclude_permanently_known` drops
innate spells from an offer, so listing one would be a dead entry that still
inflated the book size. `test_spellbook_prune.gd` asserts both that rule and
that every authored spell is in some book or explicitly excluded.

## The loot-book prune (#586)

A relic's claimant picks exactly **one** spell from whatever is offered, so the
only lever on how fast spells spread is **how often a kill offers nothing**.
That is what the prune is for — not narrowing the choice, which
`_exclude_permanently_known` already does for free.

At spawn, each Dormant Core copies its tier book and pops random spells off the
copy until a roll fails (`SpellBook.duplicate_pruned`). With `n` spells left, it
pops with probability `n / (n + m)`:

```
E[kept]      = n * m / (m + 1)
P(kept == 0) = 1 / C(n + m, n)        # integer m
```

`m = 1` is the special case where every outcome in `{0..n}` is **equally
likely** — maximum variation, and `P(empty) = 1/(n+1)`. That makes book size the
whiff dial: 50% for N=1, 33% for N=2, 25% for N=3, 20% for N=4.

**`m` is tuned DOWN to slow spell spread, never up.** Raising it keeps more
spells, so kills offer nothing *less* often — at n=4, P(empty) falls from 20%
(m=1) to 2.9% (m=3). The knob is `GraphProcgenConfig.blocker_spell_prune_m`,
range 0.5–3.0, default 1.0.

The roll is **seeded per placement** by procgen, off the same derived stream as
blocker placement. Every peer re-runs the level scene, so the prune is
reproduced rather than received — an unseeded roll would hand two peers
different offers off the same relic. See `.claude/rules/multiplayer-sync.md`.

## Why the tier ladder is not monotonic

LARGE holds a single rare spell and therefore whiffs ~50% of the time, more
often than SMALL or MEDIUM. That is accepted, not an oversight: with only eight
spells authored there is nothing else rare enough to put beside `reverberator`,
and the spells gated behind LARGE are strong enough that a 50% payout is fair.
The books are plain `.tres` arrays, so re-balancing as spells are added is an
inspector edit. A spell may appear in more than one tier — overlap raises both
tiers' payout rate, since N is the whiff dial.

Weights *within* a tier do not exist. If they are ever wanted, that is the point
to promote the books from `SpellBook` to a dedicated loot-table resource; until
then a plain array of `SpellDef` is exactly what a spellbook already is, and the
loot path reads `victim.spellbook` uniformly for every entity.
