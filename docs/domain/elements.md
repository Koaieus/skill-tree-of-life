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
- No surface reads a count yet (`docs/domain/stat-surfaces.md` § Quiver,
  volleys, infusion, ammo aspects).

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
| `ammo`, `addon_scene`, `spells` | empty until #1810, #1804 and the spell cells |
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
| `go_off` | a `GoOff` (`elements/go_off.gd`, the abstract base); Fire's Burning band holds a `DiscGoOff` (#1800), every other band null. #1798 owns the contract, #1799 / #1800 / #1806 the subclasses |
| `admits` | an `Admits` (`elements/admits.gd`, empty abstract base); null on every band. #1807 owns the answer |
| `travel` | `Travel { NONE, ENDS, CONDUCTS, SPREADS }` |
| `decay_per_world_turn` | the band's own decay rate (a knob) |
| `light` | the band is a light source |

The authored bands (tentative numbers are knobs on the `.tres`):

| element | band | threshold | identity | travel | decay | light |
|---|---|---|---|---|---|---|
| Fire | primed | ×1 | `burning` | SPREADS | 1 (tentative) | yes |
| Fire | overflow | at cap | — | SPREADS (lead call, tentative) | 2 (tentative) | #1805's |
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
  - `SaveFile` is v14, and a 13 still loads.
  - `WorldFingerprint._terrain_rows` folds `[stable_id, t, charge]`. All-zero
    nodes are skipped, so a world without terrain folds as before.
- **Not yet.** No display (#1796).

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
    seat (`seat()`, an `Array[TerrainSettle.SettleReader]`, empty today;
    #1801's prime conversion is the first reader): each reader once per node,
    with the pre- and post-batch ints and the node's sums to add to. Then it
    writes once per int through `add_terrain` (Fire for t, Lightning for
    Charge), so a band crossing is announced once per node per commit, and
    returns the nodes whose ints moved. `commit_with(batch, readers)` takes
    explicit readers.
  - Callers: the world turn, once per step and once for decay. #1798's beat
    will commit a land batch and a spend batch per generation.
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

## Burning's disc and dual reach (#1800)

Fire's Burning band authors a second `DiscGoOff` (`elements/disc_go_off.gd`) on
`elements/defs/fire.tres`. Every seam the class adds defaults to go-off zero's
value — `power_source = EXPLOSIVE_CHARGES`, `radius_source =
EXPLOSIVE_SPREAD`, `spend_source = SPEND_OF`, `damage_per_power = 0` — and
Burning sets each:

- **Power.** Heat's excess over T (`Power.HEAT_EXCESS`, `Terrain.excess` on the
  node's read), read after the hit's Heat rider has landed, the overflow past
  the cap included. Power ≤ 0 is no go-off.
- **Radius.** `DiscGoOff.disc_radius(power, node_radius)` =
  `radius_a × (√power + radius_b) ×` the origin node's radius (`Radius.DISC`).
  `radius_a` (default 2) and `radius_b` (default 1) are tentative knobs
  (#1800).
- **Spend.** `Spend.PER_NODE`: 1 Heat per other node reached, through
  `GoOffResult.cost` and the gather's `TerrainSettle` batch. A disc that
  reaches no other node spends nothing and does not go off (the base `GoOff`
  law); it has no nodeless cost.
- **Own damage.** `damage_per_power × power` on each copy and on the centre
  landing; 2 on Fire's instance (tentative knob, #1800).
- **Reach.** Shape alone (`_within`, `EuclideanRangeFinder`), the centre
  excluded; the hit's own `target_mask` decides which reached nodes take a
  copy. Its `BlastMark` names the band's identity (`Burning`).

One read of a node fires both every band's `go_off` and every aspect's
`go_off` (`HitGather._generation`, `attack/outcome/hit_gather.gd`) — dual
reach. Each go-off adds its own centre entry when `lands_on_own_node` (the base
default, true on Fire's disc). `HitGatherTunables.dedupe_dual_reach`
(`attack/outcome/hit_gather_tunables.gd`, default false) folds a node's two
copies of one head, in one generation, into one landing at the summed shares.

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

**Not yet.** Fire's overflow band has no `go_off` authored yet.
