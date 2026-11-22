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
`catalyst_aspect`, the facet `catalyst_stacks_per_hit` (no resistance),
the goo arrow, the barrel and Firecracker; it carries no `GoOff`.

- **Planting.** A row naming Catalyst takes the default `PlantUse`
  (`AspectIntake.default_use()`), so a landing plants Catalyst at its load. It
  lands only on allocated nodes, and `on_dealloc` clears it.
- **Cap.** The row's gains cap at its node's k × T (`NodeCombat.terrain_cap`,
  #1794) while `cap_k_times_t` is on, and the cap limits gains only (ADR 0096):
  `CatalystStatus.cap_on` overrides the `StatusDef.cap_on` virtual, and
  `StatusHost._settle` bounds a write that raises the row to
  `min(target, max(before, cap))`. A cap that drops (an edge removal, a stake
  extract) takes nothing away; a landing on an over-cap row adds and removes
  nothing; a reduction and a restore are written as sent. `power_max` stays 0.
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
copy's riders), the row converts over their sum before the terrain write,
and the stacks it makes join that write. They count toward the same hit's
primed-ness and power: a node at T − 4 with 3 Catalyst, hit by 2 Heat, ends at T + 1 and goes off within that hit. Copies are hits, so
a copy's Heat rider converts the reached node's Catalyst; a centre landing and
a hit with no Heat, Cold or Charge rider convert nothing. Arrivals of one
generation on one node convert once, over their summed stacks. The take is a
row op on the hit (`HitInstance.row_ops`), so the authority's replay and a
peer's take it alike. A go-off's transfer (`GoOffResult.transfer`) converts
nothing: it joins the generation's spends, never the landing sum, and no
go-off fills it yet — Shocked's Charge transfer is #1806's.

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
the row at 0. The land commit's settle reads each landed node's counts from
before the land step, so a head's own riders count as the crossing even when
the split converts nothing: Heat T with 1 Catalyst, hit by 1 Heat + 1 Charge,
ends with the row at 0.

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
carries no radius or blast logic. The shipped barrel is not temp-placeable
(`catalyst_barrel_addon.tscn`: `temp_placeable = false`), so the swing tray
never offers it; the addon still guards a temp barrel (no refill, no removal
spend, the carrier's row never written).

## The blade

A blade holds no Catalyst. `BladeVertexFill` reads no Catalyst off a piece's
source node, a contact spends nothing on the piece or the struck node, and no blast reaches blade pieces. A contact is one hit: a primed
struck node goes off through the gather as any hit sets it off, and a node
holding only Catalyst blasts nothing and keeps its stacks (no production blade rider
lands Heat, Cold or Charge to convert).

## Firecracker

`attack/spell/defs/firecracker.tres` walks an edge wave (`FanAllSpread` over
enemy nodes, `max_hops` 10, `MaxDamageReducer`), and its first row names Fire
(`innate` 6, the default `PlantUse`), so each landing plants Heat. A node the
Heat tips into Burning goes off through Burning's disc; Firecracker has no
blast of its own. A second row names Catalyst at `innate` 0: infused points
plant Catalyst beside the Heat (an intended combo). The status lands after
the hit's terrain, so the same landing's Heat does not convert it; a later
Heat landing or the node's priming does. It authors no crit.

## The look

Catalyst on a node reads as violet crystals: the node's own `StatusOverlay`
in `Layer.CATALYST` (`Visuals/CatalystLayer`, outside the health bar's fade)
draws one crystal per stack (`crystal_size`, at most `crystal_cap`). It sits
south, under #1796's terrain bars: `TerrainBars.stack_below` keeps its top at
`south_offset` while the bars are down and under the last drawn row while they
are up (tentative: it snaps on show/hide). Fog hides it like the core bar
(`StatusOverlay.concealed`, written by `SkillNode._apply_sensed_state` when the
node is neither revealed nor lantern-lit). A conversion announces the
node-local `SkillNode.catalyst_converted(converted)` (via
`announce_catalyst_converted`) — `{element id: stacks made}`, carried in the take's row op (`AttackRecord` columns `rw_cn/rw_ce/rw_cs`)
for both the landing and the settle prime — once, from the live replay of the
take (`HitGather`'s row-op apply; a shadow world stays silent). The world
turn's terrain prime has no record: `CombatWorld._world_take` announces it on
every peer's live world as `EndTurnCommand` reproduces the pass (a shadow
stays silent there too). On either path the layer flashes the crystals the
take spent (the last drawn row) in the tint of the element that made the most
stacks (`StatusOverlay.pulse_tint`; the first named on a tie), swelling by
`conversion_pulse_swell` and fading over `conversion_pulse_seconds`. The barrel (`catalyst_barrel_visual.gd`) is a pile
of faceted violet crystals on the carrier's rim, lit while the carrier holds
the matching stack; the goo arrow (`catalyst_arrow.tscn`) is a slender
crystal shard; the icon is `assets/icons/aspects/catalyst.png`.

## Knobs

All tentative, easy to change.

| knob | default | owner | what |
|---|---|---|---|
| `ratio_in` / `ratio_out` | 1 / 1 | `CatalystStatus` (`effects/status/catalyst.tres`) | the trade rate, Catalyst : landing element; editor feedback in the status sandbox tab |
| `cap_k_times_t` | true | `CatalystStatus` | cap the row's gains at its node's k × T (a dropped cap never trims); off leaves `power_max` alone |
| `per_tick` | 1.0 | the def's `FlatDecay` | Catalyst lost per world turn |
| `triggers` | death | `CatalystSpread` | which removal causes burn the row |
| `crystal_size`, `crystal_cap`, `conversion_pulse_seconds` | 5.0, 6, 0.5 | `StatusOverlay` | the look |

`CatalystSpread` authors no damage: the death burn writes the row off and
deals none, and `describe()` says so.

## Guards

`test/unit/effects/test_catalyst_conversion.gd` (the split, both triggers,
cap, allocation, the world-turn decay, the goo arrow),
`test/unit/spell/test_firecracker.gd`,
`test/unit/skill_node/test_catalyst_barrel_addon.gd`,
`test/unit/elements/test_burning_go_off.gd` and
`test/unit/elements/test_disc_go_off.gd` (the blast it feeds),
`test/unit/attack/test_blade_contact_on_primed_node.gd` (a blade contact
holds and spends no Catalyst).
