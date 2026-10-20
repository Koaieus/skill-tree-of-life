# Explosive — charges, faces, the spend/power formula, the two-sided blade contact

What *is*. The calls are ADR 0061 and ADR 0062 (the default face on
`StatusDef`, the blade's second target set), from the owner's rulings on
#1608 (comments 6176828602 and 6177810352, 2026-10-14) and #1609 (comment
6178627285). The passages still open (Flamestrike, "both" from one heal, the
death-blast carrier, the rejected list) stay in the
design record: [`docs/design/aspect_matrix.md`](../design/aspect_matrix.md) § Explosive.

## Vocabulary

- A **hit** is the catch-all: a blade contact, an arrow landing, a spell
  landing (`HitInstance` / `HitLanding` / `OnHitEffect`).
- A hit's explosive **load** is the explosive it carries: a spell row's
  DETONATE load, a blade piece's charges. An arrow carries load 0; goo
  ammo plants instead (below).
- A node's **charges** (`present`) are the Explosive status stacks on it.
  A charge is a life: a blade piece's charges are what it spends per contact.

## Charges are a status

`effects/status/explosive.tres` is a `StatusDef` (id `explosive`, tag
`charge`, `default_face = Detonate`). Its spread, `ExplosiveSpread`
(`effects/status/spread/explosive_spread.gd`), is the one owner of a
charge's boom shape: every node-centred blast asks `radius_for` /
`blast_for` and never computes a reach itself.

- **Decay**: `FlatDecay`, one charge off each turn end.
- **Death**: `ExplosiveSpread.on_removed` burns every charge of a node
  removed by a cause in `triggers` (default death only) in one transfer,
  `damage_per_charge` per charge; nothing spills onto a neighbour.
- **A core** with no charges of its own reads and spends its owner's
  entity-hosted ones (`DetonateEffect._present`).
- **Barrel addon** (`skill_node/addons/explosive_barrel_addon.gd`): not
  unique; at the owner's turn start an allocated carrier tops its charges up
  to its barrel count (flat, never stat-scaled), a barrel leaving spends one
  charge if there is one. It carries no radius or blade logic: a swung
  piece's lives are its node's charges.

## Three faces

What a hit's load does is `AspectIntake.use` (a `LoadUse`) on the spell's intake row
(`attack/spell/aspect_intake.gd`): left null (the default) it resolves through
the concept status's `StatusDef.default_face` (`resolved_use()`,
`use_for_status()`); explosive authors `DetonateUse`, every other status `PlantUse`, a
concept with no status `PlantUse`. `StatusDef.default_face` is an int enum
tagging `DetonateUse` because `effects/` may not name `attack/`.

| face | the load | where |
|---|---|---|
| **DETONATE** | spent at the hit as a blast, through the formula below; load 0 still sets off charges present | `Infusion.detonate_load` → `DetonateEffect.arm(riders, load)` in `SpellResolver`; arrows (`RangedDamageFormula.riders_for`, load 0); blade contacts (load = piece charges) |
| **PLANT** | lands as the status rider at `power = load`; spends nothing, no blast from this hit | `Infusion.riders` (one `ApplyStatusEffect` per PLANT concept); goo ammo `attack/ammo/types/explosive.tres` (an `ApplyStatusEffect` rider, `explosive_stacks_per_hit`) |
| **FUEL** | no rider; the load only shapes the spell, read from `PropagationContext.load` | Firecracker's `FuelBlastReach` (`attack/spell/propagation/reach/fuel_blast_reach.gd`) |

**The PLANT skip.** `DetonateEffect.arm` returns the effects unchanged when
any one lands explosive: a hit that plants never blasts, and a riderless hit
still detonates. The face is the carrier's author's choice (spell row, ammo
def, addon), never the player's; a PLANT row's price is its authored
affinity (house convention: about half a DETONATE row's), no per-face knob.

## Spend and power

For a DETONATE hit with `load` on a node holding `present` charges
(`attack/spell/on_hit/detonate_effect.gd`):

```
shared = min(load, present)
spent  = max(1, shared) if present > 0 else 0          # spend_of — a spark always takes one
power  = load + present + 2 · resonance · shared       # power_of; resonance = 1
       = (load + r·shared) + (present + r·shared)      # the striker's side + the node's side
```

A blast happens iff `power > 0`, so load 0 on a clean node is a plain hit.
The load is **offered, never consumed** by the formula: each reservoir pays
its own spend. An arrow has no reservoir, infusion paid at cast, a blade
piece pays `max(1, shared)` per contact (below).

| hit | present | load | power | left |
|---|---|---|---|---|
| plain arrow | 0 | 0 | none, no blast | 0 |
| plain arrow | 5 | 0 | 5 | 4 |
| load 3 | 0 | 3 | 3 | 0 |
| load 3 | 5 | 3 | 14 | 2 |
| load 3 | 1 | 3 | 6 | 0 |

Five sparks on a 5-patch fire 5, 4, 3, 2, 1 in turn. Within one compile
on the live board a per-compile ledger (`SPENT_KEY` in
`HitLanding.gather_cache`) subtracts what earlier arrows of the volley
already spent, so a volley never booms more times than the board holds; a
spell reads its cast world, where every spend has landed before the next
wave.

## The blast carries the hit

`ExplosiveSpread.blast_for(centre, power, inners)` builds a `BlastEffect`
(a `SplashEffect` that skips the centre and inherits the landing's mask)
whose reach is **the bomb is the node**:

```
reach = centre.radius × reach_per_radius × power^charge_exponent   # radius_for, fed the power
```

Uncapped; at `charge_exponent = 0.5` area is linear in power. Its inners are
a chained `DetonateEffect` (load 0), the `PairedDamageEffect` shrapnel (a
fraction of the landing's raw amount) and the hit's riders with explosive
stripped: a blast replicates the hit, never plants. It lands under the
landing's own target mask. A damage spell's landing has no paired hit; a
heal spell's landing rides its own heal (`LandingContext.ride_heal`), so its
blast heals, under the same landing mask. A heal never gates, so ADR 0044's "a
spell gates nothing" still holds for both, while its "paired stays null"
holds for damage spells only.

## Chains

A blast is a zero-load hit on each node it reaches, so a charged neighbour
goes off. `HitLanding.detonated` is the once-per-node scope: one per arrow,
one per spell wave (`SpellResolver`), shared by every splash copy
(`SplashEffect` copies it onto the copy) and pinned on each chained copy, so
nothing goes off twice in a scope. A blade's board blast carries a load-0
`DetonateEffect` and chains like any other. Blade pieces are never chained:
a pop is the blade sim's event, not a hit.

## The blade contact: one contact, two sides

`BladePopResolver.LiveGate._admit_explosive`
(`attack/melee/sim/blade_pop_resolver.gd`), on a contact by piece `idx`
with `n = piece_charges(idx)` (the swing's working copy,
`BladeState.vertex_charges`, filled by `BladeVertexFill`) on a struck node
with `m` charges (`node_charges`, less this swing's spends):

- `shared = min(n, m)`; each side holding charges spends `max(1, shared)`
  (piece: `_spend_piece`; node: `_spend_node`), both recorded as `Spend`s the
  resolve lands as cleanses.
- `side_power(own, shared) = own + resonance · shared`, 0 for a side holding
  none.
- **The striker's side** `n + r·shared` blasts the **board**: `arm_blasts`
  builds a `BlastEffect` centred on the struck node, reach
  `warhead_reach × radius_for(struck.radius, power)`, inners the piece's
  riders stripped and re-armed with a load-0 Detonate plus shrapnel at
  `shrapnel_fraction` of the contact's raw damage; it lands under the
  landing's mask (a `BlastToken` gates it on `admit`'s decision).
- **The node's side** `m + r·shared` reaches the **blade pieces** within
  `warhead_reach × radius_for(struck.radius, node_power)` of the struck
  node (`_piece_pass`): a plain piece POPS, a charged piece is armed, not
  fragile, and SHRUGS. A piece whose source node has `deflection`
  (`BladeState.vertex_shielded`, filled by `BladeVertexFill`) also SHRUGS,
  spending nothing; a charged one keeps its charges as any shrugged piece
  does. **The node's side never reaches the board.**
- The contact's own piece is SPENT, or POPPED (and its hit refused) when it
  ends at 0 charges.
- One `Contact` row per explosive contact in `Result.contacts` (time,
  centre, `piece_reach`, both powers, a verdict per piece considered), so the
  replay draws it as a pure function of time.

Owner's numbers (r = 1): 100 on 0, board 100, blade 0. 0 on 100, board 0,
the whole plain blade in reach pops. 100 on 1, board 101, blade 2. 3 on 5:
board 6, blade 8, both spend 3, the piece pops at once. A 3-charge piece on
clean nodes: 3 → 2 → 1 → pop, three shrinking warheads.

## Knobs

All tentative, easy to change.

| knob | default | owner | what |
|---|---|---|---|
| `resonance` | 1 | `ExplosiveSpread` (on `effects/status/explosive.tres`) | the shared chunk's weight on each side |
| `reach_per_radius` | 3.0 | `ExplosiveSpread` | blast reach at power 1, in the node's own radius |
| `charge_exponent` | 0.5 | `ExplosiveSpread` | reach ∝ power^this, in halves |
| `damage_per_charge` | 2.0 | `ExplosiveSpread` | death-blast damage per charge |
| `warhead_reach` | 0.5 | `BladePopResolver.LiveGate` | melee's reach share, both sides of a contact |
| `shrapnel_fraction` | 0.5 | `BladePopResolver.LiveGate` | the board blast's share of the contact's raw damage |

No `blast_radius` stat on any board: nothing targets blast size
(`docs/domain/stat-knobs-and-bins.md` §1).

## Firecracker (FUEL)

`attack/spell/defs/firecracker.tres`: each landing is a euclidean blast
whose hits are the next wave (`FuelBlastReach`, edges play no part); fuel is
the cast's explosive load less `fuel_per_jump` per hop, the radius shrinks
with it, and the cast ends at fuel 0 or `max_hops`. A hit crits when its
blast's centre shares no edge with the node. It plants no charges; every pop
is a load-0 spark that sets off charges it lands on.

## Guards

`test/unit/attack/test_explosive_charges.gd` (formula, spend, reach),
`test/unit/attack/test_blade_explosive.gd` (two sides, verdicts, chains),
`test/unit/spell/test_heal_spell_blast.gd`, `test/unit/spell/test_firecracker.gd`,
`test/unit/skill_node/test_explosive_barrel_addon.gd`.
