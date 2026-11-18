# Elements — the second axis, as the code has it

design record: `docs/design/elements.md` and `docs/design/elements/`. This
is the *what is*. Every later #1716 unit appends its part here.

An **element** sits beside the aspects, never above them: an aspect is one
status, an element is one count and a **family** of member statuses with fixed
roles. Elements are not parents of aspects, and no aspect's status is a member
(ADR 0072 §1; `test_aspect_roster.gd` guards both).

## The counts

| element | count stat | shown as | school (pool roll) | terrain stack | primed band | overflow band |
|---|---|---|---|---|---|---|
| Fire | `fire_element` | "Fire attunement" | STR (`procgen/pools/strength.tres`) | Heat | Burning | (no identity) |
| Ice | `ice_element` | "Ice attunement" | DEX (`dexterity.tres`) | Cold | Frozen | Deep freeze |
| Lightning | `lightning_element` | "Lightning attunement" | INT (`intelligence.tres`) | Charge | Shocked | (no identity) |

- Each count is `stats_system/defs/<element>_element.tres`: the element
  identity, `role = COUNT` (`StatDef.Role.COUNT`, the ordinal the old `ASPECT`
  had), no family parent, `default_value` 0 (#1809 raises it to 1). Every
  non-sparse entity board mints it through `mint_facets`; read it as
  `board.facet(&"fire", StatDef.Role.COUNT)`.
- The pool roll copies an aspect's supply entry: `passes [budget, supply]`,
  regular and blight subtypes. `test_pool_scoping.gd` (`_SUPPLY_HOME`) and
  `test_roll_pass.gd` (supply = the COUNT-role stats) pin it.
- The infusion wheel reads every `ElementRoster` count as a shown, never
  pickable wedge (`InfusionChoices._element_entries`).

## `Element` (`elements/element.gd`)

One `elements/defs/<element>.tres` per element. The fields it shares with
`Aspect` keep `Aspect`'s names.

| field | holds |
|---|---|
| `identity` | the element's `Identity` (`Kind.ELEMENT`); `id()` reads it |
| `stat` | the COUNT facet above |
| `terrain` | the one terrain stack (`StatusDef`) |
| `movers` | the sided movers; empty in v1 (Frostbite joins Ice with #1444) |
| `school` | the attribute `Identity` whose pool rolls the count |
| `ammo` | the element's arrow, `attack/ammo/types/<element>.tres` (minted from `stat`, rides `terrain`) |
| `addon_scene`, `spells` | empty until #1804 and the spell cells |
| `decay_per_world_turn` | terrain decay per world turn below the first band; 1 on all three (owner, 2026-11-11). Read by #1795 |
| `bands` | `Array[ElementBand]`, ascending |

## `ElementBand` (`elements/element_band.gd`)

A band is a threshold, an identity and its answers. Nothing computes or
stores a band here: #1794's band function reads `bands` against
(count, T, k), and returns the highest band a count passes.

| field | holds |
|---|---|
| `threshold_multiple` | the threshold as a multiple of T (≥ 1) |
| `at_cap` | true: the threshold is the node's cap k × T and `threshold_multiple` is ignored; only the last band |
| `identity` | the band's display atom; null falls back to the band below |
| `go_off` | a `GoOff` (`elements/go_off.gd`, the abstract base); Fire's Burning and overflow bands hold a `DiscGoOff` (#1800, #1803), Lightning's Shocked and overflow bands one shared `EdgeGoOff` (#1806), every other band null. #1798 owns the contract, #1799 / #1800 / #1806 the subclasses |
| `admits` | an `Admits` (`elements/admits.gd`, empty abstract base); set on both Ice bands (one `FrozenAdmits`, § Ice on the node: Frozen), null elsewhere |
| `travel` | `Travel { NONE, ENDS, CONDUCTS, SPREADS }` |
| `conduct_cost` | stacks a spell walk spends passing through a node in a CONDUCTS band; Lightning's Shocked and overflow bands 1 (tentative knob), else 0 |
| `decay_per_world_turn` | the band's own decay rate (a knob) |
| `light` | the band is a light source: every viewer sees a disc of `DiscGoOff.disc_radius(excess, R)` (§ Burning burns and lights) |
| `burn_per_excess` | world-turn TRUE damage per stack of excess on an allocated node (default 0, so only Fire's bands burn) |

The authored bands (tentative numbers are knobs on the `.tres`):

| element | band | threshold | identity | travel | decay | light |
|---|---|---|---|---|---|---|
| Fire | primed | ×1 | `burning` | SPREADS | 1 (tentative) | yes |
| Fire | overflow | at cap | — | SPREADS (lead call, tentative) | 2 (tentative) | yes (lead call, tentative) |
| Ice | primed | ×1 | `frozen` | ENDS | 1 (tentative) | no |
| Ice | overflow | at cap | `deep_freeze` | ENDS (tentative) | 2 (tentative) | no |
| Lightning | primed | ×1 | `shocked` | CONDUCTS | 1 (tentative) | no |
| Lightning | overflow | at cap | — | CONDUCTS (lead call, tentative) | 2 (tentative) | no |

An overflow band keeps its primed band's travel verb; only its decay differs
(`test_element_roster.gd` pins the verbs, and pins overflow decay ≥ primed,
never the literal). **Volatile** (Burning, Shocked) is a word, not a field.

## `ElementRoster` (`elements/element_roster.gd` + `.tres`)

The `AspectRoster` pattern: hard `ExtResource` edges, read through
`ElementRoster.shared()`, never a directory scan.

- `by_id(&"fire")`, `for_stat(&"fire_element")`.
- `for_status(def)`: the element whose `terrain` or `movers` holds `def`, or
  null. This is the one way to ask "is this status a member, and of what".
  Catalyst is nobody's member, so it answers null.

Guard: `test/unit/elements/test_element_roster.gd` (roster vs disk, lookups,
facet identities, band order, Fire's one `DiscGoOff` and null admits, verbs,
light, decay).

## The terrain statuses: Heat, Cold, Charge

`effects/status/{heat,cold,charge}.tres`: the plain `StatusDef` script, each on
its own identity, no tags, `power_max = 0` (uncapped here; the cap is the
node's k × T, #1794). They stay on `effects/status_roster.tres`, but a landing
never makes a row: `NodeCombat.apply_status` diverts them into the node's
terrain ints (§ Terrain, below).

Each member keys its own facets: `heat_resistance`, `cold_resistance`,
`charge_resistance` (`role = RESISTANCE`, parent `status_resistance`, the
`poison_resistance` shape), on `stat_def_roster.tres` and minted on every
board. No `*_stacks_per_hit` facet: a member lands its authored power as-is.

## Terrain: two ints of node state (#1794)

Terrain is side-less node state. A band is derived at every read and never
stored. Guards: `test/unit/combat/test_terrain_state.gd` (landing, index,
fingerprint) and `test_terrain_bands.gd` (the band sweep, the signal).

- **The facts.** `NodeState.terrain_t` is signed, Heat minus Cold.
  `NodeState.charge` is Lightning's and never goes below 0. That is all of
  it. `clone()` copies both, so a shadow sees live terrain on first touch.
  Both are saved, replicated and fingerprinted.
- **The arithmetic.** `Terrain` (`combat/terrain/terrain.gd`) is static,
  pure and integer only:
  - `threshold(d)` is T = `t_per_degree × d`. It always reads graph
    degree (`degree.md`).
  - `cap(d, k)` is `k × T`.
  - `count_of(state, element)`: Fire = max(t, 0), Ice = max(−t, 0),
    Lightning = charge. The axis is keyed by element id in `axis_of`,
    since `Element` has no polarity field.
  - `band_of(element, count, T, cap)` returns the highest band whose
    threshold the count passes. That threshold is `threshold_multiple × T`,
    or the cap when `at_cap`. A count ≤ T gives null.
  - `excess` is past T and `overflow` is past the cap.
- **The knobs** (tentative):
  - `TerrainRules.t_per_degree` lives in `combat/terrain/terrain_rules.tres`,
    default 2, shared with #1795, #1796 and #1798.
  - `terrain_cap_k` is a node-board scalar: base 2 on
    `default_node_board.tres` plus an ADD_BASE intrinsic reading
    `stake_scaling.tres` (the stake cap, not the fill). Bare ground
    (stake 1) holds k = 3. `NodeCombat.terrain_cap()` mints an unowned
    node's board before it reads k.
- **The one writer** is `NodeCombat.add_terrain(element, delta)`.
  - A shadow (`host == null`) writes its clone's int and returns.
  - A live slice reads the band of every element the write can move (Fire
    and Ice share t), writes and reindexes. Then, for each element whose
    band changed, it calls `host.notify_terrain_band_changed`, which emits
    `SkillNode.terrain_band_changed(element, from, to)`.
  - Drops are emitted before rises, so a sign flip of t reads as Fire's
    band leaving and then Ice's arriving.
- **The landing divert.** `NodeCombat.apply_status` asks
  `ElementRoster.for_status(def)`.
  - An element's `terrain` def becomes
    `add_terrain(element, round_half_up(power))` and never reaches
    `StatusHost`: no row, no camp, no applier, no `_may_host`. Unallocated
    nodes take it.
  - `*_resistance` does not filter it (open, #1798).
  - Movers and every other def land as rows, unchanged.
- **The live index.** `CombatWorld` keeps an insertion-ordered set of live
  slices with t ≠ 0 or charge > 0, the `_lingering` shape: `note_terrain`,
  `forget_terrain`, `reindex_terrain`, `holds_terrain` and `terrain_nodes`.
  - `add_terrain` keeps it in step, and `GraphSnapshot` decode rebuilds it
    per node.
  - A shadow world refuses it.
  - #1795's world-turn pass gathers from it (§ Flow).
- **Replication.**
  - `GraphSnapshot`: `_R_TERRAIN_T` = 20 and `_R_CHARGE` = 21
    (`_ROW_SIZE` 22). A shorter row decodes as 0.
  - `SaveFile` is v15; anything older is refused (`network/save_file.gd`).
  - `WorldFingerprint._terrain_rows` folds `[stable_id, t, charge]`. All-zero
    nodes are skipped, so a world without terrain folds as before.
- **Display.** `TerrainBars` (`skill_node/terrain_bars.tscn`) on every
  `SkillNode`'s `Visuals`.

## Flow: the world-turn settle (#1795)

Terrain changes between beats on the world turn only. Guards:
`test/unit/combat/test_terrain_settle.gd` (the commit),
`test_temperature_flow.gd` (the pass) and
`test/unit/systems/test_world_turn.gd` (the clock and the call).

- **The clock.** `TurnManager.world_clock` is an exported rate rule,
  `WorldClock.{PER_CARRIER, CEIL_SQRT}`, default `PER_CARRIER`: a world turn
  every N played turn ends, N = the living carriers (ADR 0055, unchanged).
  `CEIL_SQRT` closes one every ⌈√N⌉, found by an integer loop in the pure
  `world_turn_period(n, clock)`. `_note_played_turn_end` compares progress
  `>=` the period. Turnless hosts and lingering rows ride whichever rule is
  set. `terrain_steps_per_world_turn` (default 1, tentative) is the number of
  diffusion steps a world turn runs.
- **The call.** `_end_world_turn` runs `CombatWorld.flow_temperature(steps)`
  after `tick_lingering` and before `flush_removals`: the steps, then one
  decay sweep. A shadow world refuses it.
- **Diffusion** (`diffuse_temperature`, one step from one snapshot). It
  gathers the indexed nodes with t ≠ 0, and their graph neighbours as
  receivers, into a dense order on packed arrays (t, graph degree, each edge
  once). It never walks the graph. Per edge it moves
  `⌊gap / (1 + max(deg_u, deg_v))⌋` from hot to cold, so Σt is conserved, a
  gap at or below the larger degree moves nothing and a self-loop moves
  nothing. The per-node sums commit as one batch. `FractionDiffusion` (rows,
  float share) is not reused: temperature is node state, not a row.
- **Decay** (`decay_terrain`, once after the steps). Every indexed node's t
  moves toward 0 and its Charge down by `TerrainSettle.decay_rate`: the
  current band's `decay_per_world_turn`, or the element's own when the count
  is ≤ T (null band). Heat and Cold read Fire / Ice by t's sign, Charge reads
  Lightning. Every rate is read before any write, so an overflowing node
  loses the overflow's whole rate even where that ends it below the cap.
  Charge never flows.
- **The commit.** `TerrainSettle` (`combat/terrain/terrain_settle.gd`) is
  static and pure.
  - A `TerrainSettle.Batch` holds per-node `Sums`: `net_t` (signed, nets
    through 0), `toward_zero_t` (≥ 0, never crosses 0) and `charge` (signed,
    the result clamped at 0).
  - `commit(batch)` applies the net, then toward zero. It runs the settle
    seat (`seat()`, an `Array[TerrainSettle.SettleReader]`: one
    `PrimeConversion` per `CatalystStatus` the status roster authors): each reader once per node,
    with the pre- and post-batch ints and the node's sums to add to. Then it
    writes once per int through `add_terrain` (Fire for t, Lightning for
    Charge), so a band crossing is announced once per node per commit, and
    returns the nodes whose ints moved. `commit_with(batch, readers)` takes
    explicit readers.
  - Callers: the world turn, once per step and once for decay. `HitGather`'s
    beat commits a land batch and a spend batch per generation.
- **Determinism.** Integer only, roll-free, no transcendental. The index's
  order never reaches the ints, and a world decoded from a `GraphSnapshot`
  ends its next world turn on the same ints as its source.

## `Identity.Kind.ELEMENT`

Appended last (ordinal 5), so stored kinds do not shift; presentation only.
Ten identities use it: `fire`, `ice`, `lightning`, `heat`, `cold`, `charge`,
`burning`, `frozen`, `shocked`, `deep_freeze`. Their hues clear the roster's
same-kind OKLab separation and the gold exclusion (`test_identity_roster.gd`).
The badge frame is a triangle (`ui/identity_badge/badge_frames.tres`, key 5).
`concept_card.gd` stays ASPECT-only; the identity sandbox lists the kind
through `Kind.values()`.

## Intake rows name their status

`AspectIntake.plants` (`attack/spell/aspect_intake.gd`): when set, `status()`
returns it; null falls back to the concept's only status through
`AspectIntake.concept_status` (an element's terrain, else
`StatusRoster.by_concept`). No shipped row sets it yet; #1800 rekeys
`Infusion.load_of` / `use_of` so a row named by element resolves its status
(below).

## Burning's disc (#1800)

Fire's Burning band authors a `DiscGoOff` (`elements/disc_go_off.gd`) on
`elements/defs/fire.tres`, the only blast; no aspect hosts a disc. The class
has one power source and one radius law; `fire.tres` sets only `damage_per_power`:

- **Power.** Heat's excess over T (`Power.HEAT_EXCESS`, `Terrain.excess` on the
  node's read), read after the hit's Heat rider has landed, the overflow past
  the cap included. Power ≤ 0 is no go-off.
- **Radius.** `DiscGoOff.disc_radius(power, node_radius)` =
  `radius_a × (√power + radius_b) ×` the origin node's radius.
  `radius_a` (default 2) and `radius_b` (default 1) are tentative knobs
  (#1800).
- **Spend.** 1 Heat per other node reached (the base `GoOff` law), through
  `GoOffResult.cost` and the gather's `TerrainSettle` batch. A disc that
  reaches no other node spends nothing and does not go off (the base `GoOff`
  law); it has no nodeless cost.
- **Own damage.** `damage_per_power × power` on each copy and on the centre
  landing; 2 on Fire's instance (tentative knob, #1800).
- **Reach.** Shape alone (`_within`, `EuclideanRangeFinder`), the centre
  excluded; the hit's own `target_mask` decides which reached nodes take a
  copy. Its `BlastMark` names the band's identity (`Burning`).

One read of a node fires every band's `go_off` (`HitGather._generation`,
`attack/outcome/hit_gather.gd`). Each go-off adds its own centre entry when
`lands_on_own_node` (the base default, true on Fire's disc).
`HitGatherTunables.dedupe_dual_reach` (`attack/outcome/hit_gather_tunables.gd`,
default false) folds a node's two copies of one head, in one generation, into
one landing at the summed shares.

**The ride row's rekeying.** An intake row named by an element resolves its
status by that element (`AspectIntake.concept_status` asks
`ElementRoster.by_id` first), so `Infusion.load_of` / `use_of` and its riders
carry it. A Heat row resolves to Heat, and a `PlantUse`'s `ApplyStatusEffect`
lands as terrain: Heat goes into the node's terrain and no status row is
planted (§ Terrain's landing divert).

**The look.** A disc's `BlastMark` names its go-off, and `BlastVFX.look_for`
(`ui/vfx/blast_vfx.gd`) finds the element whose band identity that is, so
`apply_look` gives the `BlastVisual` (`ui/vfx/blast_visual.gd`) that element's
colour and a filled disc.

Fire's overflow band authors its go-off: `elements/defs/fire.tres`'s `band_overflow` carries the `burning_disc` `go_off`.

## Fire's add-up (#1828)

A Fire shape and a Burning node go off as ONE disc (ADR 0084 §3, §4), on the
same `DiscGoOff` as Burning's disc (`elements/disc_go_off.gd`):

- **Radius.** `DiscGoOff.shape_disc_radius(shape_power, excess, node_radius)` =
  `radius_a × (√shape_power + √excess + radius_b) ×` the origin node's radius;
  each root's term is floored at 0. It is the one formula: `disc_radius(power, R)`
  is `shape_disc_radius(0, power, R)`.
- **The fire.** `DiscGoOff.fire_shaped_in(world, node, read, shape_power)`, beside
  `fire_in` (which is unchanged). The caller computes the shape power: a blade
  vertex passes its excess at fill (#1829), a cast passes points ×
  `shape_power_per_point` (#1812).
- **Burning node** (`power_at` > 0). It reaches every node inside the combined
  radius. It pays its **solo cost**, 1 per reached node that is also inside its
  own `disc_radius(excess)`, which is the same spend `fire_in` makes there. When
  the combined disc reaches anyone and that spend is below
  `solo_cost_floor`, the shortfall goes into `nodeless_cost`. `solo_cost_floor`
  defaults to 1, `@export_range(0, 3)`, and 0 turns it off (tentative knob,
  #1828). `power` and `own_damage` (`damage_per_power × excess`) read the
  excess only, and `reach` is the combined radius.
- **Node not Burning** (Heat ≤ T, or Cold). The shape runs alone over
  `shape_disc_radius(shape_power, 0, R)`, with no spend, no power and no own
  damage. With shape power ≤ 0 as well, it is no go-off.
- A disc that reaches nobody spends nothing, the floor included.
- **What stays with the callers.** The caller routes the answer through
  `HitGather`: the one Fire channel, whether a centre copy lands (ADR 0086 §4,
  §5), and who spends what.

## The Burning vertex and the Heat addon (#1829)

- **The Heat addon** (`skill_node/addons/defs/heat_addon.tscn`, look
  `skill_node/addons/visuals/heat_visual.gd`): Fire's element addon, rider only,
  one `ApplyStatusEffect` of `heat` at `power = 1` (tentative knob), costing 1
  `fire_element`. Its vertex lands that Heat on every contact the gate admits.
- **The Burning vertex.** A vertex whose terrain copy sits in a band that goes off
  by a `DiscGoOff` (Fire's Burning: copy > T at fill) is a **Fire shape on the
  node it touches**, of shape power copy − T (`power_at` on the copy), centred on
  and sized by the contact node. `HitGather._fire_source` hands a disc band to
  `_fire_vertex_disc`, which calls `fire_shaped_in` on the contact node's read:
  - **Contact node Burning**: one Fire channel. The node's own plain `fire_in`
    is skipped for that hit (`_vertex_disc`), the combined disc lands the
    centre copy and mints one mark, and the node pays its solo cost (floored).
  - **Contact node not Burning** (Frozen included): the shape runs alone, with a
    mark but no centre copy (`_append_reach`'s `centre_copy = false`), no node
    spend, no own damage; the mark's `power` is 0.
  - The copy pays 1 per node the disc reaches, through the source's spend
    (tentative pass pick: the alternative is the copy pays nothing beyond the
    node's solo cost). A disc reaching nobody spends nothing. The source node is
    never touched; a later contact goes off only while the copy stays > T.
  - A go-off whose disc is not a `DiscGoOff` keeps the generic source path.
- Guards: `test/unit/attack/melee/test_burning_vertex.gd`,
  `test/unit/attack/melee/test_heat_addon.gd`.

## Lightning: Shocked arcs and conducts (#1806)

- **The arc** (`elements/edge_go_off.gd`, `EdgeGoOff`). Lightning's Shocked and
  overflow bands hold the same instance (`lightning.tres`; the overflow band
  sharing it is a lead call, tentative). A node in either band that is read
  after a hit's riders land goes off, so a rider tipping Charge from T to T + 1
  sets it off at once. The arc reaches every node within L hops of the centre,
  allocated or not, centre excluded. The reach is one BFS,
  `GraphMirror.nodes_within`, sorted by depth then instance id. Each reach
  carries its hop depth. At depth ≥ 2 its `ring` names the depth − 1 neighbours
  it hangs behind (the gather's hop seat: [spell-propagation.md](spell-propagation.md)
  § Resolver flow). Its share is `.share`, its own damage 0, and the answer
  ignores the hit's load.
- **The ladder** (`level_of`). L is the highest level ≤ `max_level` with
  Charge > L^`ladder_exponent` × T, and 0 (inert) at Charge ≤ T. It reads the
  whole count, never count − k × T, so a node past the cap arcs on the same
  ladder. With a T of 0, any Charge ≥ 1 reads straight to `max_level` (0 at
  Charge 0).
- **Cost and transfer**, within the node's own level M only. Each node reached
  within M hops costs 1, itemised in `GoOffResult.cost`. On the default
  `spent_charge_goes_to` (Reached node), that node also takes the spent stack
  as `transfer`. On Void, no stack moves. A node reached only through an added
  level (beyond M) costs nothing and takes nothing.
- **`fire_level_in(world, node, read, added)`** is the entry point for an extra
  level. It is one go-off at M + `added` hops from `node` (never `read.node`),
  paying M's solo cost. `added` = 0 is the plain `fire`. M = 0 with an added
  level is a shape alone: it reaches but pays nothing. `max_level` caps only
  M; `added` goes on top uncapped, so a combined arc can exceed it.
- **Conduction.** Shocked and overflow are `travel` CONDUCTS with
  `conduct_cost` 1. `HitGather._conduct` runs in the go-off loop at the node's
  read, for the head's own node only, and only if the head `walk_spreads`. It
  spends the cost into the read's spend batch, so a conduct and an arc on one
  arrival settle as one summed spend, and it marks the head `conducted`. The
  walk side is in [spell-propagation.md](spell-propagation.md) § `max_hops`.
- **The Shocked vertex.** A vertex whose Charge copy sits in an `EdgeGoOff`
  band is a Lightning shape on the node it touches. It arcs at the copy's level
  (`level_of` on the copy's read). `HitGather._fire_source` hands it to
  `_fire_vertex_arc`:
  - **Contact node Shocked**: one Lightning channel. The node's own plain arc
    is skipped for that hit (`_vertex_arc`). One arc goes out at the node's
    level plus the copy's (`fire_level_in`), with one mark and the centre copy,
    and the node pays its solo cost (within M) off its store, each such stack
    transferring to its reached node. The copy's own stacks never transfer, so
    a node within M costs two stacks, of which only the node's moves.
  - **Contact node not Shocked**: the copy's arc runs alone, with a mark but no
    centre copy, and no node spend. On the Reached-node default each node
    reached takes the copy's transferred stack; on Void nothing moves.
  - Either way the copy pays 1 per node reached, through the source's spend:
    depth 1 at this read, deeper nodes as `_release` lets them on
    (`_Fired.copy_spend`). An arc reaching nobody is no go-off. A later contact
    arcs only while the copy stays > T.
  - Not built: the Frozen-contact mute (#1807, #1808).
- **The Charge addon** (`skill_node/addons/defs/charge_addon.tscn`, look
  `skill_node/addons/visuals/charge_visual.gd`). This is Lightning's element
  addon, rider only: one `ApplyStatusEffect` of `charge` at `power = 1`
  (tentative knob), costing 1 `lightning_element`.
- **Tentative knobs**: `ladder_exponent` 2, `max_level` 3,
  `spent_charge_goes_to` Reached node, and `conduct_cost` 1.
- **Guards**: `test/unit/elements/test_shocked_go_off.gd`,
  `test/unit/spell/test_shocked_conduction.gd`,
  `test/unit/attack/melee/test_shocked_vertex.gd`,
  `test/unit/attack/melee/test_charge_addon.gd`.

## Burning burns and lights (#1805)

Both are reads of a node's Fire band; nothing stores Burning. Fire's two
bands each author `burn_per_excess = 1.0` (the owner's "1 per stack", read as
per stack above T; tentative knob), and both have `light`. The overflow band
burning and lighting like Burning is a lead call (tentative): it uses the
whole excess, Heat − T, never Heat − k × T. Guards:
`test/unit/elements/test_burning_burn.gd` and
`test/unit/systems/test_vision_sources.gd`.

- **The burn.** `CombatWorld.burn_terrain()` walks the live terrain index
  (`terrain_nodes()`). Every allocated node whose Fire band sets
  `burn_per_excess` takes `burn_per_excess × excess` through `DotTick.mint`.
  That is TRUE damage with no record, so the floater and a kill come from
  the same door a poison tick uses. The burn ignores camps and lands nothing
  on an unallocated node. Amounts come from one snapshot; a node that an
  earlier burn in the pass left unheld takes nothing. `TurnManager._end_world_turn`
  calls it after `tick_lingering` and before `tick_world_turn_decay` /
  `flow_temperature`, so it reads the pre-diffusion t. It is not in
  `TerrainSettle`, which stays pure (a grep pin). `EndTurnCommand` replays it
  on every peer, and its removals go out in the turn's one `flush_removals`.
  A holder's death, a dealloc or a retake never touch t, so the next holder
  burns.
- **The light.** `VisionSource.Kind.BURNING`: `VisionSystem.sources_for`
  gives one disc per node whose Fire band has `light`, for every viewer.
  The radius is `DiscGoOff.disc_radius(excess, the node's own radius)`,
  called through Fire's `bands[0].go_off` and never copied. Detail and the
  refresh trigger are in `docs/domain/vision-system.md` § Burning nodes.

## Ice on the node: Frozen (#1807)

Ice's answers are one `FrozenAdmits` (`elements/frozen_admits.gd`), authored
once in `elements/defs/ice.tres` and set as `admits` on **both** Ice bands
(Frozen and Deep freeze; tentative lead reading: `band_of` hands a node past
the cap only the overflow band, so the one resource keeps both answering
alike). Ice owns no gather code and no terrain write: `HitGather` asks both
seams and settles the answer (hit-resolution.md § The beat).

- **A breaker, each arrival alone** (`FrozenAdmits.breaks`): the head's crit
  (decided at the beat's open, so a blade contact's and an arrow's too), or —
  on a node with a holder — the arrival's damage as the floater shows it
  (`mitigated`: `HitPoints.whole`, then `Mitigation.compute` with the node's
  `armor` / `min_damage_taken` and the head's pierce; TRUE unmitigated) at or
  above `break_fraction_max_hp` × the holder's max HP. The holder is
  `world.combat_for(node).owner()`; no holder, no flat breaker. A merged dual
  reach (`dedupe_dual_reach` on) is one arrival at its summed amount.
- **The admit** (`admit_in`, before the generation's riders): a copy that does
  not break is absorbed (no entry; its terrain riders still land). A head and a
  centre copy always land.
- **The read** (`read_in`, after the riders, once per node per generation;
  asked only while the node is still Frozen or Deep freeze, so a thaw is no
  breaker): `breakers` = every arrival that breaks (centre copies skipped); none
  → `paths_end`. On a break: `extra_landings = break_channels`,
  `spend = round(excess × shatter_spend_fraction)` of the node's own excess
  (count − T, overflow included: deep freeze), and
  `burst = (excess + added_excess(...)) × shatter_fraction_per_stack × holder max
  HP`, 0 with no holder. `added_excess` is 0: the seat a cast's concentrate
  (#1813) overrides; it never reaches the spend.
- **Knobs** (all `@export` on the resource, tentative): `break_fraction_max_hp`
  0.10, `break_channels` 2, `shatter_fraction_per_stack` 0.01,
  `shatter_spend_fraction` 1.0, and `vertex_bonus_per_excess` 0.10 (the Frozen
  blade vertex's multiplier, read at fill, not by either answer).
- **The Cold addon** (`skill_node/addons/defs/cold_addon.tscn`, look
  `skill_node/addons/visuals/cold_visual.gd`): Ice's element addon, rider only,
  one `ApplyStatusEffect` of `cold` at `power = 1`, costing 1 `ice_element`.
- **A blade on Frozen.** The gate (`BladePopResolver.LiveGate.admit`) decides
  as the beat opens, before any rider lands, so it never refuses a contact for
  ice: every contact on Frozen lands. The touch is a third breaker in `breaks`,
  the direct contact only (never its copies): `BladeDamageInstance.touch_weight`
  — `weight_of(source radius)` × every `BunkerAddon.blade_mass` on its source,
  `weight_of(r) = (r / MASS_REF_RADIUS)²` — at least the node's
  `weight_of(SkillNode.radius)` (a tie breaks). The pop needs the node Frozen
  as the beat opens (`admit` notes it) and still Frozen after the contact's
  riders: `read_in` is asked only then, so every blade contact it is handed
  that `admit` noted pops its vertex there (`_snap_blades` → `snap_on_ice` →
  `LiveGate.snap`, `_kill` at the contact's `t`, no drain), breaker or not. A
  contact whose own Heat thawed the node is never read, and one whose own Cold
  froze it was not noted: either vertex lives on. The head carries the pop
  (one-shot or ice) from its own landing, so the break's extra landings and
  go-off copies carry none. The pivot is exempt. Terrain is side-less:
  unallocated Frozen ground (the scan sees it) takes the contact too, where
  any other unallocated node is refused (no dud); own and allied nodes never
  reach the gate (`collect_target_excludes`).
- **The Frozen vertex** (`BladeVertexFill`): a vertex whose copy reads an Ice
  band answered by a `FrozenAdmits` is flagged `vertex_one_shot` (the gate lands
  its first contact, then pops it, whatever the riders), and its `blade_damage`
  read folds one MULTIPLY bin of `1 + vertex_bonus_per_excess × copied excess`.
  The source node is only read.
- Guards: `test/unit/attack/test_frozen_admits.gd`,
  `test/unit/attack/test_ice_shatter.gd`, `test/unit/attack/test_blade_frozen.gd`.

## Pair rules: Frozen mutes, the break releases (#1808)

What needs two elements at once (`docs/design/elements/frozen.md` § Pair rules),
as built. One branch of code, the rest pins on what Fire, Lightning and Ice built.

- **The mute** is `HitGather._read_node`'s return, read by the go-off loop of
  `_generation`. The node's second `Admits` read (once per node per generation,
  after every arrival's terrain riders landed) yields one verdict, keyed on the
  `AdmitsAnswer`, never on Ice by name: no answer → every hit there goes off as
  before; an answer that ends paths and has no breaker → **no hit goes off
  there** (the node's other bands' go-offs are dropped: nothing spent, nothing
  reached, no centre landing; Charge landed meanwhile, a rider's or an arc's
  transfer, stays on the node — "trapped"); a break → only the hits owning a
  breaking arrival go off, **once each, each with its own payload** (ADR 0093
  §3, tentative pending playtest), a hit the ice absorbed sets nothing off. The
  shatter's spend and the released go-offs' spends commit in the same batch.
- Riders first: a Heat rider that thaws the node lifts the mute for its own
  generation (no shatter: a thaw is no breaker), a Cold rider that freezes a
  Shocked node mutes it. The released arc reads its level after the breaker's
  riders, so a breaker carrying Charge feeds the arc it releases.
- A blade vertex's shape on a muted node runs alone (`_fire_vertex_arc` /
  `_fire_vertex_disc` with `muted`): the node's own arc stays trapped, the
  vertex arcs with no centre copy and no node spend.
- A spell walk's conduct is not a go-off and is not muted; a Frozen node that
  holds ends the walk anyway (`path_ends`).
- **Landing counts** (b = `FrozenAdmits.break_channels`, 2): a Frozen + Shocked
  node hit under the threshold takes 1; broken, 1 + b + 1 (the released arc's
  centre) plus the burst, each neighbour 1; two breakers in one beat: one
  burst and one shatter spend, 2 + 2b + 2, each neighbour 2, the arcs' spends
  summed and clamped at 0. A Burning + Shocked node takes 3, a node both reach
  2 (two marks; one landing at share × 2 with `dedupe_dual_reach` on), the
  terrain riders once per node per hit. A copy onto a Frozen node is absorbed
  under the threshold (its Heat, Cold and Charge still land, the go-off still
  pays for it); a breaking copy lands and takes b, two breaking copies of one
  hit take 2 + 2b with one burst.
- Catalyst under a Frozen node converts with whatever terrain lands there, an
  absorbed copy's Cold included.
- **The look**: `TerrainBars.is_trapped(node, element)` — the element's band
  goes off and another band the node sits in answers `Admits` — read from the
  bands alone. A trapped bar's fill leans toward the holding band's tint
  (`trapped_frost`, tentative), its Charge blips dim, its frame takes the
  tint, and `label_for` ends in `TRAPPED_SUFFIX`, so the tooltip's terrain row
  reads it too.
- Guards: `test/unit/attack/test_element_pairs.gd`.
