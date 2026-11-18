# Catalyst — the store, the trade, both triggers, cap, decay, barrel, goo arrow

What *is*. Catalyst is an element-generic converter that sits on a node: the
Heat, Cold or Charge that lands on its node, or the band its node primes
into, takes the store with it. The calls are the owner's (2026-11-09 and
2026-11-11), recorded on #1801.
Design record: [`docs/design/elements/terrain.md`](../design/elements/terrain.md) § The threshold model.
Design record: [`docs/design/aspect_matrix.md`](../design/aspect_matrix.md) § Catalyst. The
blast is Burning's disc, never Catalyst's: [elements.md](elements.md)
§ "Burning's disc (#1800)".

Where the land conversion sits in one hit's landing (the walk, the beat, rider
order): [hit-resolution.md](hit-resolution.md) § "Catalyst at the land step".

## The status

`effects/status/catalyst.tres` is a `CatalystStatus` (`effects/status/catalyst.gd`,
a `StatusDef`): id `catalyst`, tag `catalyst`, identity
`identity/defs/catalyst.tres` (violet). The Catalyst `Aspect`
(`aspects/defs/catalyst.tres`, school DEX) names it with the count
`catalyst_aspect`, the facets `catalyst_stacks_per_hit` / `catalyst_resistance`,
the goo arrow, the barrel and Firecracker; it carries no `GoOff`.

- **Planting.** A row naming Catalyst takes the default `PlantUse`
  (`AspectIntake.default_use()`), so a landing plants Catalyst at its load. It
  lands only on allocated nodes, and `on_dealloc` clears it.
- **Cap.** The row caps at its node's k × T (`NodeCombat.terrain_cap`, #1794)
  while `cap_k_times_t` is on: `_on_applied` trims a landing or a move that took
  it past. `power_max` stays 0.
- **Decay.** `FlatDecay`, `per_tick` 1.0 (the default), once per **world
  turn**, never at its holder's turn end: the def sets
  `StatusDef.decay_per_world_turn`, so `StatusHost` skips the row in
  `tick_statuses` and `CombatWorld.tick_world_turn_decay` ticks it, run by
  `TurnManager._end_world_turn` right after `tick_lingering`. The live world
  keeps the holders in `CombatWorld._world_turn_decay`. Its loss per world turn
  stays at or under the Fire band's `decay_per_world_turn` (a pinned
  invariant, both read from the defs).
- **Death.** Its spread, `CatalystSpread`
  (`effects/status/spread/catalyst_spread.gd`), burns a removed node's whole
  row in one transfer on a cause in `triggers` (default death only); nothing
  spills onto a neighbour. The burn writes the row off and deals no damage of
  its own.

## The trade

`CatalystStatus.converted(store, landing)` is the pure split: landing stacks
by element id in, Catalyst parts by element id out, the store's leftover being
`store` minus their sum. It takes no primary element; only the landing Heat,
Cold and Charge stacks count. Each element's share `store × w / W` is
floored, the stacks left go one per element down the remainders, largest
first, a whole tied group at a time, and a group the leftover cannot cover
stays Catalyst ([rounding.md](rounding.md), the Catalyst row).

| store | landing | converts | left |
|---|---|---|---|
| 3 | 2 Heat | 3 → Heat (node gains 5 Heat) | 0 |
| 3 | 1 Heat + 2 Charge | 1 Heat, 2 Charge | 0 |
| 5 | 1 Heat + 2 Charge | 2 Heat, 3 Charge (shares 1.67, 3.33) | 0 |
| 3 | 1 Heat + 1 Charge | 1 Heat, 1 Charge | 1 |
| 1 | 1 Heat + 1 Charge | nothing (tied) | 1 |

Each part trades at `ratio_in` : `ratio_out` (`traded`: `part × ratio_out /
ratio_in`, integer division); `spent` takes the least Catalyst that buys
those stacks, so the rest of a part stays Catalyst. `CatalystStatus.convert`
is the one door that takes a node's row: split, trade, take the spent
Catalyst off the row (or hand it to a `take` callable), and return the stacks
to land. The converted stacks obey the element's k × T cap and overflow like
any other landing.

## Two triggers

**At land.** `HitGather._convert_landing` runs once per node per land commit:
when Heat, Cold or Charge stacks land on a node holding Catalyst (a hit's or a
copy's riders, an arc's transferred Charge), the row converts over their sum
before the terrain write, and the stacks it makes join that write. They count
toward the same hit's primed-ness and power: a node at T − 4 with 3 Catalyst,
hit by 2 Heat, ends at T + 1 and goes off within that hit. Copies are hits, so
a copy's Heat rider converts the reached node's Catalyst; a centre landing and
a hit with no Heat, Cold or Charge rider convert nothing. Arrivals of one
generation on one node convert once, over their summed stacks. The take is a
row op on the hit (`HitInstance.row_ops`), so the authority's replay and a
peer's take it alike.

**At settle.** `TerrainSettle.PrimeConversion` (`combat/terrain/terrain_settle.gd`),
one reader per `CatalystStatus` in the status roster, runs at every commit of
the settle seat: a land batch, a spend batch, every world-turn diffusion step
and the decay sweep. When a commit takes Heat, Cold or Charge from inert
(≤ T) to primed (> T), the whole row left converts into that element and
joins the same write. Two counts crossing in one commit split the store by
their excess past T (tentative). Flow at or below T never converts, and an
already-primed node does not convert again. It is never hooked on
`terrain_band_changed`, which stays display-only. A landing that splits and
also primes converts at land first; the settle then converts the leftover:
Heat T − 1 with 3 Catalyst, hit by 1 Heat + 1 Charge, ends at Heat T + 2 and
the row at 0.

## The goo arrow

`attack/ammo/types/catalyst.tres` ("Catalyst Arrow", `order` 2) is a plain
arrow whose one rider is an `ApplyStatusEffect` of Catalyst, its power folded
through `catalyst_stacks_per_hit`; it plants as a poison arrow plants Poison. A
planting hit is a hit: on a primed node it sets it off, and its copies carry
the Catalyst rider over the disc. It lands no Heat, Cold or Charge, so the
node's own Catalyst is neither converted nor lost. The element arrows as ammo
are #1810's.

## The barrel

`skill_node/addons/catalyst_barrel_addon.gd`, not unique: at the owner's turn
start an allocated carrier tops its Catalyst up to its barrel count (flat,
never stat-scaled), and a barrel leaving takes one off if there is one. It
carries no radius or blast logic.

## Firecracker

`attack/spell/defs/firecracker.tres` walks an edge wave (`FanAllSpread` over
enemy nodes, `max_hops` 10, `MaxDamageReducer`), and its first row names Fire
(`innate` 6, the default `PlantUse`), so each landing plants Heat. A node the
Heat tips into Burning goes off through Burning's disc; Firecracker has no
blast of its own. A second row names Catalyst at `innate` 0: infused points
plant Catalyst beside the Heat (an intended combo). The status lands after
the hit's terrain, so the same landing's Heat does not convert it; a later
Heat landing or the node's priming does. It still authors
`NoEdgeToSourceCondition` as its crit (a hit whose payload `predecessor`
shares no edge with the node), a leftover of the old euclidean walk that the
edge wave never meets.

## The look

Catalyst on a node reads as violet crystals: `StatusOverlay` draws one
crystal per stack (`crystal_size`, at most `crystal_cap`). A conversion
announces `Events.catalyst_converted(node, spent)` once, from the live replay
of the take (`HitGather`'s row-op apply; a shadow world stays silent), and the
overlay flashes a pulse on that node that fades over
`conversion_pulse_seconds`. The barrel (`catalyst_barrel_visual.gd`) is a pile
of faceted violet crystals on the carrier's rim, lit while the carrier holds
the matching stack; the goo arrow (`catalyst_arrow.tscn`) is a slender
crystal shard; the icon is `assets/icons/aspects/catalyst.png`.

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

changing: `resonance` goes with the blade's piece pass, #1802; see docs/design/elements/go-offs.md

All tentative, easy to change.

| knob | default | owner | what |
|---|---|---|---|
| `ratio_in` / `ratio_out` | 1 / 1 | `CatalystStatus` (`effects/status/catalyst.tres`) | the trade rate, Catalyst : landing element; editor feedback in the status sandbox tab |
| `cap_k_times_t` | true | `CatalystStatus` | cap the row at its node's k × T; off leaves `power_max` alone |
| `per_tick` | 1.0 | the def's `FlatDecay` | Catalyst lost per world turn |
| `triggers` | death | `CatalystSpread` | which removal causes burn the row |
| `resonance` | 1 | `CatalystSpread` | the blade piece pass's shared-chunk weight (#1802's) |
| `crystal_size`, `crystal_cap`, `conversion_pulse_seconds` | 5.0, 6, 0.5 | `StatusOverlay` | the look |

`CatalystSpread.damage_per_charge` is still authored, and `describe()` still
promises it, but no code reads it: the death burn writes the row off and deals
no damage.

## Guards

`test/unit/effects/test_catalyst_conversion.gd` (the split, both triggers,
cap, allocation, the world-turn decay, the goo arrow),
`test/unit/spell/test_firecracker.gd`,
`test/unit/skill_node/test_catalyst_barrel_addon.gd`,
`test/unit/elements/test_burning_go_off.gd` and
`test/unit/elements/test_disc_go_off.gd` (the blast it feeds),
`test/unit/attack/test_blade_explosive.gd` (the piece's side, #1802's).
