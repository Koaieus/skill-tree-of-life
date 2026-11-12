# Explosive — charges, faces, the spend/power formula, go-off zero, the blade contact

What *is*. The calls are ADR 0061 and ADR 0062 (the default face on
`StatusDef`, the blade's second target set), from the owner's rulings on
#1608 (comments 6176828602 and 6177810352, 2026-10-14) and #1609 (comment
6178627285). The passages still open (Flamestrike, "both" from one heal, the
death-blast carrier, the rejected list) stay in the
design record: [`docs/design/aspect_matrix.md`](../design/aspect_matrix.md) § Explosive.

changing: the Explosive aspect is retagged Catalyst, go-off zero is deleted and this doc becomes `catalyst.md`, #1801; see docs/design/elements/terrain.md

Where a detonation sits in one hit's landing (the walk, the beat, rider order): [hit-resolution.md](hit-resolution.md) § "Go-off zero: Explosive detonation".

## Vocabulary

- A **hit** is the catch-all: a blade contact, an arrow landing, a spell
  landing (`HitInstance` / `HitLanding` / `OnHitEffect`).
- A hit's explosive **load** is the explosive it carries, its head's
  `HitInstance.hit_load`: a spell row's detonate load, a blade piece's charges. An arrow carries load 0; goo
  ammo plants instead (below).
- A node's **charges** (`present`) are the Explosive status stacks on it.
  A charge is a life: a blade piece's charges are what it spends per contact.

## Charges are a status

changing: a swung blade piece no longer carries its node's charges, #1802; see docs/design/elements/go-offs.md

`effects/status/explosive.tres` is a `StatusDef` (id `explosive`, tag
`charge`, `default_face = Detonate`). Its spread, `ExplosiveSpread`
(`effects/status/spread/explosive_spread.gd`), is the one owner of a
charge's boom shape: go-off zero's disc (`DiscGoOff`) asks `radius_for`
and never computes a reach itself.

- **Decay**: `FlatDecay`, one charge off each turn end.
- **Death**: `ExplosiveSpread.on_removed` burns every charge of a node
  removed by a cause in `triggers` (default death only) in one transfer,
  `damage_per_charge` per charge; nothing spills onto a neighbour.
- **A core** with no charges of its own reads and spends its owner's
  entity-hosted ones (`DiscGoOff.present_on`).
- **Barrel addon** (`skill_node/addons/explosive_barrel_addon.gd`): not
  unique; at the owner's turn start an allocated carrier tops its charges up
  to its barrel count (flat, never stat-scaled), a barrel leaving spends one
  charge if there is one. It carries no radius or blade logic: a swung
  piece's lives are its node's charges.

## Three faces

changing: `FuelUse` is deleted, #1801; see docs/design/elements/go-offs.md

What a hit's load does is `AspectIntake.use` (a `LoadUse`) on the spell's intake row
(`attack/spell/aspect_intake.gd`): left null (the default) it resolves through
the concept status's `StatusDef.default_face` (`resolved_use()`,
`use_for_status()`); explosive authors `DetonateUse`, every other status `PlantUse`, a
concept with no status `PlantUse`. `StatusDef.default_face` is an int enum
tagging `DetonateUse` because `effects/` may not name `attack/`.

| use | the load | where |
|---|---|---|
| `DetonateUse` | spent at the hit as go-off zero's load, through the formula below; load 0 still sets off charges present | `LoadBag.detonate_load` (`DetonateUse.spend`) → each head's `hit_load` (`SpellResolver`'s stamper); an arrow's is 0; a blade contact's is its piece's charges (`LiveGate.stamp_load`) |
| `PlantUse` | lands as the status rider at `power = load`; spends nothing, no blast from this hit | `LoadBag.riders` via `PlantUse.spend` (one `ApplyStatusEffect` per `PlantUse` concept); goo ammo `attack/ammo/types/explosive.tres` (an `ApplyStatusEffect` rider, `explosive_stacks_per_hit`) |
| `FuelUse` | no rider; the load only shapes the spell, read from `PropagationContext.load` | Firecracker's `FuelBlastReach` (`attack/spell/propagation/reach/fuel_blast_reach.gd`) |

**The PlantUse skip.** A hit whose span carries an Explosive row (a
`PlantUse` rider, goo ammo) does not set go-off zero off (`HitGather._plants`):
a hit that plants never blasts, and a riderless hit still goes off. The face is the carrier's author's choice (spell row, ammo
def, addon), never the player's; a `PlantUse` row's price is its authored
affinity (house convention: about half a `DetonateUse` row's), no per-face knob.

## Spend and power

Go-off zero is the Explosive detonation as a disc `GoOff`: `DiscGoOff`
(`elements/disc_go_off.gd`), authored as `Aspect.go_off` on
`aspects/defs/explosive.tres`. `HitGather` fires it at a node's read, once per
node per hit ([hit-resolution.md](hit-resolution.md) § "Go-off zero: Explosive
detonation"). For a hit carrying `load` on a node holding `present` charges:

```
shared = min(load, present)
spent  = max(1, shared) if present > 0 else 0          # DiscGoOff.spend_of — a spark always takes one
power  = load + present + 2 · resonance · shared       # DiscGoOff.power_of; resonance = 1
       = (load + r·shared) + (present + r·shared)      # the striker's side + the node's side
```

A go-off happens iff `power > 0`, so load 0 on a clean node is a plain hit.
`present` is the node's stored Explosive row as the arrival's generation
starts: the pre-beat store for a beat's own arrivals, the store the
generation before left for a copy (ADR 0091 §1). No rider of the triggering
hit joins it. The spend is committed whatever the disc reaches, a lone charged
node included (lead call, tentative), on the holder's row, summed with the
generation's other spends there and clamped at 0. The load is **offered,
never consumed** by the formula: each reservoir pays its own spend. An arrow
has no reservoir (infusion is paid at cast); a blade piece pays
`max(1, shared)` per contact off its own working copy (below).

| hit | present | load | power | left |
|---|---|---|---|---|
| plain arrow | 0 | 0 | none, no blast | 0 |
| plain arrow | 5 | 0 | 5 | 4 |
| load 3 | 0 | 3 | 3 | 0 |
| load 3 | 5 | 3 | 14 | 2 |
| load 3 | 1 | 3 | 6 | 0 |

Five sparks on a 5-patch fire 5, 4, 3, 2, 1 in turn, with no ledger: each
arrow is its own beat (`outcome_schedule.gd`, one entry per hit outside a
spell), so it lands and spends on the world before the next arrow reads.
Arrivals of one beat on one node (two landings of one spell wave, two blade
contacts of one sample) each go off from one read of the node. Their spends
are summed and clamped at 0.

## The blast carries the hit

The disc takes every node within its reach of the centre, the centre
excluded, by shape alone, allocated or not (`DiscGoOff._within`, over the
graph's global `Navigator`). The hit's own target mask then decides which of
them take a copy: a node it misses takes none and does not chain. The reach
is **the bomb is the node**:

```
reach = centre.radius × reach_per_radius × power^charge_exponent   # ExplosiveSpread.radius_for, fed the power
```

Uncapped; at `charge_exponent = 0.5` area is linear in power. The gather
lands a copy of the triggering hit's whole span on each node the disc takes,
one generation later. A copy is `paired` to the head, carries its crit, and
deals damage × `share` with each status rider at ceil(stacks × `share`), one
row per status. Go-off zero adds no damage of its own. Go-off zero authors
`share` 0.5 and `lands_on_own_node` false (lead call, tentative, until the
Catalyst retag), so the struck node takes the hit alone and each disc node
takes one copy at half the damage. A copy never plants explosive, because a
hit that plants never goes off. A damage spell's landing has no paired hit. A
heal spell's landing rides its own heal (`LandingContext.ride_heal`), so its
copies heal at `share` × the heal, under the same landing mask. A heal never
gates, so ADR 0044's "a spell gates nothing" still holds for both, while its
"paired stays null" holds for damage spells only.

Each go-off that reaches a node mints one `BlastMark` (centre, reach, power,
the copies' status rider ids, the generation it fired at) and stamps it on
every copy. `OutcomeApplier` announces it once (`Events.blast_landed`) and
`BlastVFX` draws the disc from it, staggering a cascade's discs by
generation (`generation_stagger`).

**Burning's disc** is a second `DiscGoOff`, on Fire's Burning band
(`elements/defs/fire.tres`). Its power is Heat's excess over T, its radius
`disc_radius`, its spend 1 Heat per node reached, its own damage
`damage_per_power` × power, and it lands share 1 with a centre landing. A node
both charged and Burning sets off both discs at its one read:
[elements.md](elements.md) § "Burning's disc and dual reach (#1800)".

## Chains

A copy is a load-0 hit on the node it lands on, so a charged node a copy
reaches goes off in turn, one generation later, reading the store the
generation before left. The once-per-node set is the hit's: a node where a
hit already went off takes a later copy of that hit as a landing only and does
not go off again. Another hit of the same beat may still set it off. A chained
copy carries the root hit's payload flat (damage × share, riders
ceil(r × share)), never share². Blade pieces are never chained: a pop is the
blade sim's event, not a hit.

## The blade contact: one contact, two sides

changing: the blade's explosive path (vertex charges, the two-sided contact, the charge beads, a barrel on the blade) is removed, #1802; see docs/design/elements/go-offs.md

`BladePopResolver.LiveGate._admit_explosive`
(`attack/melee/sim/blade_pop_resolver.gd`), on a contact by piece `idx`
with `n = piece_charges(idx)` (the swing's working copy,
`BladeState.vertex_charges`, filled by `BladeVertexFill`) on a struck node
with `m` charges read live (`node_charges`):

- `shared = min(n, m)`; a charged piece spends `max(1, shared)` off its
  working copy (`_spend_piece`). Nothing is written to its source node, and
  the struck node's charges are never the gate's to spend.
- The contact's own piece is SPENT, or POPPED (and its hit refused) when it
  ends at 0 charges.
- **The board side is the gather's.** `LiveGate.stamp_load` stamps the
  piece's charges as the contact's `hit_load` as the batch is built, and the
  struck node's go-off zero reads it like any head's load (power, spend,
  reach and mask as above). Contacts of one sample are one beat, so two of
  them on one node both read the pre-beat charges.
- One `Contact` row per charged contact in `Result.contacts` (time, centre,
  both sides' `side_power`, the piece's verdict), so the replay draws it as a
  pure function of time. No side reaches the blade pieces: `piece_reach`
  stays 0 and no piece is SHRUGGED.

The owner's numbers (r = 1): 100 on 0, the piece spends 1 and the node goes
off at 100. 3 on 5: the piece spends 3 and pops at once, and the node keeps
its 5 for the gather. A 3-charge piece on clean nodes: 3 → 2 → 1 → pop.

## Knobs

changing: the knobs go with the Catalyst retag, #1801; see docs/design/elements/go-offs.md

All tentative, easy to change.

| knob | default | owner | what |
|---|---|---|---|
| `resonance` | 1 | `ExplosiveSpread` (on `effects/status/explosive.tres`) | the shared chunk's weight on each side |
| `reach_per_radius` | 3.0 | `ExplosiveSpread` | blast reach at power 1, in the node's own radius |
| `charge_exponent` | 0.5 | `ExplosiveSpread` | reach ∝ power^this, in halves |
| `damage_per_charge` | 2.0 | `ExplosiveSpread` | death-blast damage per charge |
| `share` | 0.5 | go-off zero's `DiscGoOff` (`Aspect.go_off` in `aspects/defs/explosive.tres`) | a copy's share of the hit: damage × share, riders ceil(r × share) |
| `lands_on_own_node` | false | go-off zero's `DiscGoOff` | no copy on the struck node |

No `blast_radius` stat on any board: nothing targets blast size
(`docs/domain/stat-knobs-and-bins.md` §1).

## Firecracker (`FuelUse`)

changing: Firecracker's row names Fire and plants Heat; `FuelUse` and `FuelBlastReach` are deleted, #1801; see docs/design/elements/terrain.md

`attack/spell/defs/firecracker.tres`: each landing is a euclidean blast
whose hits are the next wave (`FuelBlastReach`, edges play no part); fuel is
the cast's explosive load less `fuel_per_jump` per hop, the radius shrinks
with it, and the cast ends at fuel 0 or `max_hops`. A hit crits when its
blast's centre shares no edge with the node. It plants no charges; every pop
is a load-0 spark that sets off charges it lands on.

## Guards

`test/unit/attack/test_explosive_charges.gd` (formula, spend, reach, chains),
`test/unit/elements/test_disc_go_off.gd` (the disc, the whole-hit alternative),
`test/unit/attack/test_gather_aspect_go_off.gd`, `test/unit/attack/test_blast_mark.gd`,
`test/unit/attack/test_blade_explosive.gd` (the piece's side, verdicts),
`test/unit/spell/test_heal_spell_blast.gd`, `test/unit/spell/test_firecracker.gd`,
`test/unit/skill_node/test_explosive_barrel_addon.gd`.
