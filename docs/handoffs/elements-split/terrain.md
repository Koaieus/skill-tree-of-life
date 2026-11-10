The second child of the #1716 elements split: terrain becomes node state. It covers two ints on `NodeState`, their replication, T / k / cap / overflow, the band function, `terrain_band_changed`, the live index of nodes holding terrain, and Heat / Cold / Charge landings writing the ints. It adds no decay, no world-turn pass and no display. Design home: `docs/design/elements.md`. Parent hub: #1716.

Blocked by: #{defs}
Blocks: #{flow}, #{terrain-ui}, #{resolver}

## Acceptance spec

**Decisions**
- Terrain is node state (owner, 2026-11-09): *"these are actually just node state no? … imho it's a property of a SkillNode"*, and *"if it is modified mid combat, the combat mirror world might need to know about it"*. That means two ints on `NodeState`: the signed `t`, and Charge. Heat, Cold and Charge stay `StatusDef`s, and landing one writes the node's ints, never a host row (`elements.md:276-284`).
- T = 2 × graph degree, primed at count > T (owner, 2026-11-08): *"T = 2*graph_degree, so a leaf node fits 2 stacks of any without any effects, the third would be 3"* (`elements.md:50-53`).
- k = 2 + `stake_level` (owner, 2026-11-06): *"k = 2 (base value) + stake_level (statformula)"*. It is a derived rule on the node board, and the cap k × T is soft (`elements.md:288-294`).
- The overflow (owner, 2026-11-06): *"a 2nd "post cap" state sounds good too … the excess is there but burns off quickly"*. These are stacks past k × T (`elements.md:909-915`).
- A state is pure threshold (owner, 2026-11-05): *"Yes, pure threshold"*. It is derived at every read and never saved (`elements.md:285-287`).
- Heat and Cold net as one signed `t` (owner, 2026-11-05): *"option 1, 100%. hell yeah"* (`elements.md:927-935`). Charge stays put (owner, 2026-11-08): *"charge staying put sounds good"* (`elements.md:964-965`).
- A holder's death changes nothing (owner, 2026-11-08, picked *terrain persists*; `elements.md:263-266`).
- Charge decays in the world-turn pass with Heat and Cold (owner, 2026-11-10, picked the world-turn pass over decay on read):
  - Terrain stays exactly two ints.
  - There is no write-turn field and no world-turn counter.
  - One live index holds the nodes that carry any terrain.
  - The one writer announces every band crossing.

  The "decay on read" build note (`elements.md:982-984`) is dead, and #{flow} corrects it. This unit has no decay code.
- The node announces a band crossing: the one write path compares the band before and after and emits one `terrain_band_changed(element, from, to)` (pass pick, tentative; `elements.md:876-882`).

**Knobs** (tentative defaults, easy to change)
- `TerrainRules.t_per_degree`: `@export_range(1, 8, 1)`, default 2 (owner). It lives in one shared resource, `combat/terrain/terrain_rules.tres`, because #{flow}, #{resolver} and #{terrain-ui} read it too. Never a const.
- `terrain_cap_k`: a node-board scalar with base 2 (owner) plus a derived rule of +1 per `stake_level` (owner), following the manage-stats derived-rule checklist. Bare ground (stake 1) gives k = 3.

Tests assert the ratios (`count > t_per_degree × degree`, cap = k × T), never 2 or 3.

**Composition**
- **`NodeState`** owns the facts: `terrain_t: int` (heat − cold) and `charge: int`, nothing else. `clone()` (`node_state.gd:67-88`) copies them, so every shadow world sees terrain on first touch.
- **`Terrain`** (`combat/terrain/terrain.gd`, static, pure, integer only) owns the arithmetic:
  - `threshold(graph_degree)`
  - `cap(graph_degree, k)`
  - `count_of(state, element)`: Fire = max(t, 0), Ice = max(−t, 0), Lightning = charge.
  - `band_of(element, count, T, cap) -> ElementBand`: the highest of #{defs}'s bands whose threshold the count passes. A band's threshold is `threshold_multiple × T`, or the cap when `at_cap`. The result is null when the count is ≤ T.
  - `excess` and `overflow`.

  T always reads graph degree (`skill_node.gd:1330`, `docs/domain/degree.md:8-21`), never entity degree or `get_neighbours().size()`.
- **`NodeCombat`** owns the one write path, `add_terrain(element: Element, delta: int)`. It reads the band of every element the write can move, writes the int (Charge is clamped at 0, and `t` is signed), reads the band again, and for each element that changed calls `host.notify_terrain_band_changed(element, from, to)` when live. A shadow never notifies (the existing `host == null` branch). #{flow}'s pass (decay and diffusion) and #{catalyst} write through it too; there is no second writer. #{flow} may add a batched form that keeps one emit per crossing.
- **The live terrain index.** `CombatWorld` holds a live-only registry of nodes whose `t != 0` or `charge > 0`, the same shape as `_lingering` (`combat_world.gd:190-204`). `add_terrain` notes a node when it goes non-zero and forgets it when it returns to zero, and only on a live slice. #{flow} gathers its packed arrays from this index and never walks the graph. No shadow world runs a world turn.
- **`SkillNode`** declares `signal terrain_band_changed(element: Element, from: ElementBand, to: ElementBand)`. A sign flip of `t` emits twice: Fire's band leaves and Ice's arrives.
- **The landing divert.** `NodeCombat.apply_status` (`:620`) asks `ElementRoster.for_status(def)`. If the def is an element's `terrain`, it calls `add_terrain` with the power rounded per `docs/domain/rounding.md` (Cold is negative on `t`), and `StatusHost` never sees it: no row, no camp, no applier, and no `_may_host` check (terrain is owner-blind, so unallocated nodes take it). Every other def goes to the host unchanged.
- **Replication.**
  - `graph_snapshot.gd`: `_R_TERRAIN_T` = 20, `_R_CHARGE` = 21, `_ROW_SIZE` = 22. A shorter row decodes to 0.
  - `save_file.gd`: `FORMAT_VERSION` 13 → 14, with a history line. `MIN_FORMAT_VERSION` stays 13, since short rows decode.
  - `world_fingerprint.gd`: a `_terrain_rows` fold of stable id, `t` and charge, skipping all-zero nodes. The ints need no quantization.
  - On decode, the receiving peer rebuilds the live index.
- **What dies.** Nothing. The three `StatusDef`s keep identity, facets and rider duty.

**Files touched**
- New: `combat/terrain/terrain.gd`, `combat/terrain/terrain_rules.gd`, `combat/terrain/terrain_rules.tres`, `stats_system/defs/terrain_cap_k.tres`.
- Edited: `skill_node/node_state.gd`, `skill_node/skill_node.gd`, `combat/node_combat.gd`, `combat/combat_world.gd`, `stats_system/node_stat_board.gd` + `stats_system/stat_def_roster.tres` + the default node board (k), `network/graph_snapshot.gd`, `network/save_file.gd`, `command/world_fingerprint.gd`.
- Docs: `docs/domain/degree.md` (T reads graph degree). The design doc's decay build note is #{flow}'s file.

**Acceptance**
1. New `test/unit/combat/test_terrain_state.gd`:
   - A Heat landing on an unallocated node raises `terrain_t` and adds no status row.
   - Cold lowers it, and Heat 3 then Cold 2 nets to `t` = 1.
   - Charge is independent of `t` and never goes below 0.
   - A non-member status still lands as a row.
2. New `test/unit/combat/test_terrain_bands.gd`: a sweep over graph degree 1..6 × stake 1..5.
   - A count ≤ T gives null.
   - A count of T + 1 up to the cap gives the primed band.
   - A count of cap + 1 gives the `at_cap` band.
   - Every expected value is computed from `TerrainRules` and `terrain_cap_k`.
3. Signal, same file:
   - A live node crossing T emits exactly one `(element, null, primed)`.
   - A write within a band emits nothing.
   - A sign flip of `t` across both thresholds emits two.
   - A write back under T emits `(element, primed, null)`.
   - A shadow write emits nothing.
4. Index, same file. On a live node:
   - The first terrain write notes the node.
   - A write back to zero (`t` = 0 and charge = 0) forgets it.
   - A shadow write never touches the index.
   - A decoded snapshot rebuilds it.
5. `test/unit/combat/test_node_combat_state.gd` gets a new test: a shadow snapshot reads the live ints, and a shadow write leaves the live `NodeState` untouched.
6. Replication:
   - `test/unit/network/test_graph_snapshot.gd`: both fields round-trip, and a 20-column row decodes to 0.
   - `test/unit/network/test_save_file.gd`: version 14 saves, a 13 still loads, and a v14 `row_layout_hash` pin is added (`save_file.gd:20-22`).
   - A fingerprint test: two graphs differing only in one node's `t` fold differently, and equal terrain folds equal. If any of the 25 fingerprint tests pins a literal hash, re-point it.
7. `mise run mp:e2e` passes, since `network/` and `command/` are gated by it.
8. Characterization pins: `test_node_state.gd`, `test_status_linger.gd`, `test_graph_snapshot*.gd`, `test_blocker_*_join.gd`, `test_turn_cursor_crosses.gd` and `test_outcome_fixture_replay.gd` stay green unchanged.
9. Visual: none in this unit. Every child-2 visual bullet (bars, label, tooltip, glow, cues) is #{terrain-ui}, which is blocked by this unit and #{flow}.

**NOTES**
- Whether `<member>_resistance` filters a terrain write is not settled in the doc. Today resistance filters at the host, which terrain bypasses. This unit writes the rounded power it is handed. Parked for #{resolver} / the element units.
- All decay (Heat, Cold and Charge, with the overflow bands' rates from #{defs}), diffusion, the world-turn rate rule and the shared settle routine are #{flow}'s.
- Catalyst's conversion is #{catalyst}. Its prime-time read sits in #{flow}'s settle seat, never on `terrain_band_changed` (pass pick, tentative).
- Generator keystones are #1787. The no-parent go-off has no caller in any unit.
- Not here: the next element ADR's corrections are a sibling issue.

**Stubs on master**: none. The shapes are named in Composition, and the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:43-53 — inert to T, T = 2 × graph degree, excess, overflow
docs/design/elements.md:257-302 — terrain is side-less node state; cap k × T, k = 2 + stake_level
docs/design/elements.md:864-882 — bands on the Element def; the write path announces crossings
docs/design/elements.md:909-923 — the soft cap and the overflow
docs/design/elements.md:925-980 — Heat × Cold one signed t; Charge stays put; world clock
docs/design/elements.md:982-994 — build note: the index and the pass (its decay-on-read line is stale; #{flow} fixes)
skill_node/node_state.gd:14-88 — fields, ensure_board, clone()
combat/node_combat.gd:98-114 — snapshot(): how a shadow takes its NodeState copy
combat/node_combat.gd:610-621 — apply_status forwarding: the divert point
combat/status_host.gd:76-92 — apply_status: what terrain bypasses
combat/combat_world.gd:190-204 — the _lingering registry: the index's shape
network/graph_snapshot.gd:10-34 — the _R_* slots and _ROW_SIZE
command/world_fingerprint.gd:62-88 — the per-node status fold to mirror
network/save_file.gd:20-48 — version history and the bump point
docs/domain/degree.md:8-21 — the three degree accessors
skill_node/node_state.gd — seam: the two ints
skill_node/skill_node.gd — seam: owns NodeState (84); gains terrain_band_changed and notify_*
combat/node_combat.gd — seam: add_terrain, the apply_status divert
combat/combat_world.gd — seam: the live terrain index
combat/entity_combat.gd — seam: shadow_for clones lazily (379-413)
network/graph_snapshot.gd — seam: encode 216 / decode 277 rows
network/save_file.gd — seam: FORMAT_VERSION
command/world_fingerprint.gd — seam: the fold
stats_system/node_stat_board.gd — seam: stake_level (43); k's home
test/unit/test_node_state.gd — seam: NodeState pins
test/unit/combat/test_node_combat_state.gd — seam: shadow state
test/unit/effects/test_status_linger.gd — seam: registry pattern pins
test/unit/network/test_graph_snapshot.gd — seam: row round-trip
test/unit/network/test_save_file.gd — seam: format version
test/unit/attack/test_outcome_fixture_replay.gd — seam: fingerprint replay
```
