Elements, child "flow": the world turn's terrain settle. It covers an exported rate rule for the clock (linear by default, so nothing changes), one integer Heat/Cold diffusion pass, decay of all three terrain stacks, and the shared commit routine the resolver later calls once per beat. Parent hub #1716; design home `docs/design/elements.md`.
Blocked by: #{terrain}
Blocks: #{terrain-ui}, #{resolver}

## Acceptance spec

**Decisions**
- *"option 1"* (owner, 2026-11-05): diffusion, terrain decay and the terrain settle run on the world turn as built (`docs/design/elements.md:916-918`).
- *"possibly revise the rate at which the world clock ticks. like maybe speed it up with the number of entities (but not linearly? idk)"* (owner, 2026-11-05; the doc's pass knob is `ceil(sqrt(N))`, `:919-925`).
- *"Same rule, linear default"* (owner, 2026-11-10). The turn manager exports a rate rule: per-carrier (today) or integer ceil-sqrt. The default is per-carrier: no behaviour change, ADR 0055 stands, and there is no superseding ADR. Turnless hosts and lingering rows follow whichever rule is set.
- *"option 1, 100%. hell yeah"* (owner, 2026-11-05): Heat and Cold are one signed `t`, and Metropolis `floor((t_i − t_j) / (max(d_i, d_j) + 1))` runs per edge from one snapshot (`:893-901`).
- *"if we make each node lose e.g. at least 1 heat/cold (towards net 0) per tick, it should eventually cool off"* (owner, 2026-11-08; `:209-215`). Heat/Cold decay runs inside this pass.
- *"In the world-turn pass, with Heat/Cold"* (owner, 2026-11-10): Charge decays here too. Terrain stays exactly two ints, with no write-turn field and no world-turn counter. One live index holds the nodes with any terrain, and the one writer announces every band crossing. Decay-on-read is dead.
- Catalyst's prime conversion is read inside this unit's settle routine, at a seat it exposes, and is never hooked on `terrain_band_changed` (pass pick, tentative, 2026-11-10).
- The pass is the **only** implementation. It runs over the live terrain index on packed arrays, never walks the graph, and has no GDScript mirror (pass, `:929-941`).
- One snapshot per beat (owner, 2026-11-09: *"option 1. and can we make it order independent somehow?"*, then picked *one snapshot per beat*; the settled doc text, `:693-703`): hits of one beat settle terrain from one snapshot, summed and clamped at 0, and the routine is the one the world-turn tick needs. This unit builds that routine. #{resolver} calls it.
- The settle is roll-free and obeys the transcendental ban (pass write-back, ADR 0081 §9; `:728-742`).

**Knobs** (tentative defaults, easy to change)
- `TurnManager.world_clock` is an enum `{PER_CARRIER, CEIL_SQRT}`, default `PER_CARRIER` (owner). It sets the world-turn period. Editor feedback: none (a rule); `game_root.tscn` shows the node.
- `TurnManager.terrain_steps_per_world_turn` is `@export_range(1, 8, 1, "or_greater")`, default 1 (`:919`). It is the number of diffusion steps per world turn, each from a fresh snapshot.
- The decay amounts are not knobs here. Each is the band's decay-rate answer on the Fire / Ice / Lightning `Element` def (#{defs}), so the overflow band decays at its own fast rate.

**Composition**
- **The clock.** `TurnManager` owns it. `static func world_turn_period(n: int, clock) -> int` is pure. `PER_CARRIER` returns `maxi(1, n)`. `CEIL_SQRT` returns the smallest `s >= 1` with `s * s >= n`, found by an integer loop (`s = 1; while s * s < n: s += 1`, where n is the living-carrier count and stays small). The code never calls `sqrt`/`ceil` on floats, so the value is exact on every platform. `_note_played_turn_end` compares progress against this period, keeping its `>=`. Turnless hosts and lingering rows need no change: they already run inside `_end_world_turn`.
- **The terrain index** is #{terrain}'s: the one live index on `CombatWorld`, shaped like `_lingering` (`combat_world.gd:185-218`), noted and forgotten by the terrain write door when a node has any terrain (`t != 0` or Charge `!= 0`), live-only, never saved, never sent, and rebuilt on decode. This unit reads that index and builds no second one, no second note/forget hook and no graph walk. (The `host != null` shadow guard, `node_combat.gd:768-775`, is the pattern #{terrain} follows.)
- **The pass.** `CombatWorld.flow_temperature(steps)` is called from `TurnManager._end_world_turn` after `tick_lingering`, before `flush_removals`. Each step:
  - Gathers the indexed nodes with `t != 0`, plus their neighbours as receivers into a dense order of packed arrays (`t`, graph degree via `get_graph_degree` (the same degree T reads), edges once each).
  - Computes per edge `q = gap / (1 + max(deg_u, deg_v))`, where gap is the positive difference, flowing hot to cold. That is the doc's floor, computed once per edge, so Σt is conserved. Integer division of a positive gap equals floor. A self-loop moves nothing.
  - Commits the summed deltas through the settle routine.
  After the steps, one decay sweep moves every indexed node's `t` toward zero, and its Charge down, each by its own band's decay rate. The rates are read from one snapshot, and the sweep commits through the same routine. Charge never flows, only decays. The result does not depend on the index's order.
- **The settle routine** (`TerrainSettle`, pure, static) takes one batch of per-node sums computed against one snapshot:
  - `net_t` is signed: riders and flow, and it nets through zero.
  - `toward_zero_t >= 0` holds spends and decay, and never crosses zero.
  - `charge` is signed and clamped at 0.
  - Per node it applies net first, then toward-zero.
  - It then runs the **settle seat**: `readers: Array[SettleReader]`, a plural array that is empty here. Each reader gets the node with its pre- and post-batch values, and may add deltas to the same node's sums before the write. #{catalyst}'s prime conversion is the first reader.
  - It writes the result once through #{terrain}'s write door, which announces any band crossing once.
  - It returns the nodes whose ints moved.
  #{resolver} calls it once per beat generation; the world turn calls it per step and for decay. Nothing else writes terrain ints in bulk.
- **What dies:** the hard-wired linear clock, which becomes the default value of the rule. `FractionDiffusion` (status rows, float share, Dictionaries) is untouched and is not reused: temperature is node state, not a row.

**Files touched**
- `systems/turn_manager.gd`: the knobs, `world_turn_period`, the counter compare, and the pass call. Add a line to the doc comments at 27-29 and 99-105 that N is read through the rate rule.
- `docs/design/elements.md:929-941`: correct the build note. Charge decays in the world-turn pass with Heat and Cold (owner, 2026-11-10), not on read. Terrain is two ints with no write-turn field. The index holds any terrain. Fix the `:211-212` "Charge likewise" sentence to match if it reads otherwise. Run `mise run docs-hygiene` afterwards.
- `scenes/game_root.tscn`: only if the default is overridden there (otherwise none).
- `combat/combat_world.gd`: `flow_temperature` (the index itself is #{terrain}'s; read it).
- `combat/terrain_settle.gd` (new; put it beside #{terrain}'s write door if that unit chose a `combat/terrain/` folder).
- `docs/domain/rounding.md`: two rows, the world-turn period (up, integer search, `TurnManager.world_turn_period`) and the temperature flow per edge (down, hot to cold, remainder stays on the sender, `CombatWorld.flow_temperature`).
- `docs/domain/multiplayer-sync-model.md:105-107`: already widened. Name `TerrainSettle` as the auditable site, nothing more.
- `docs/domain/status-effects.md:43-46` and `docs/domain/turn-manager.md`: add one clause naming the rate rule (default unchanged).
- The domain doc #{terrain} wrote: a "Flow" section with the what-is above.
- `docs/adr/`: none. ADR 0055 stands (owner, 2026-11-10).
- Tests: `test/unit/systems/test_world_turn.gd`, `test/unit/combat/test_temperature_flow.gd` (new), `test/unit/combat/test_terrain_settle.gd` (new).

**Acceptance**
1. `test_world_turn.gd`: `world_turn_period` swept over n = 0..100. For `CEIL_SQRT`, `s*s >= n` and `(s-1)*(s-1) < n` (s >= 1). For `PER_CARRIER`, `max(1, n)`. Red first.
2. `test_world_turn.gd`: the existing cases are characterization pins and stay green **un-re-pointed** (owner, 2026-11-10). New cases set `world_clock = CEIL_SQRT`:
   - 4 carriers close a world turn every 2 played turn ends.
   - A death that shrinks the period below progress closes it at the next played turn end.
3. `test/unit/systems/test_turnless_tick.gd`, `test/unit/effects/test_status_linger.gd` and `test/unit/network/test_turn_cursor_crosses.gd` pass unchanged.
4. `test_temperature_flow.gd`:
   - A diffusion step conserves Σt and never raises Σt².
   - A gap ≤ `max deg` moves nothing (the dead band).
   - A +6 leaf beside a −6 leaf ends at 0/0.
   - The decay sweep moves every node's `t` toward 0, and its Charge down, by each band's rate. Neither crosses 0, and Charge never flows to a neighbour.
   - Two runs with the index filled in reverse order give identical ints.
   - `terrain_steps_per_world_turn = 2` equals two single steps.
5. `test_temperature_flow.gd`: a shadow world never runs the pass. A Charge-only node is in #{terrain}'s index until its Charge decays out, and a node at `t = 0` with no Charge has left the index after the pass. A world restored from a `GraphSnapshot` gives the same ints as the source after one world turn.
6. `test_terrain_settle.gd`:
   - Net then toward-zero order: `t=+3, net −5, toward 1` gives −1.
   - Charge clamps at 0.
   - A batch is order-independent.
   - A band crossing announces once per node per commit.
   - The returned changed set is exact.
   - A stub `SettleReader` is called once per node in the batch. Its added delta lands in that node's single write.
7. `mise run lint-transcendentals` and `mise run check` are clean. No RNG call in the new files. `mise run mp:e2e` reports 0 divergences.

**NOTES**
- A per-node "terrain hit" (the no-parent go-off) is a defined shape with no caller (pass ruling 5). Burning's burn is #{fire}'s. Neither rides this unit.
- Performance: the doc's worst case is ~9k integer edge updates per world turn. The drone reports one headless timing on a 3k-node hot board in its report. A C++ port only if a profile says so, and it then *replaces* this pass.
- All terrain decay is this unit's. #{terrain} writes no decay code and keeps no world-turn counter (owner, 2026-11-10).
- The next element ADR's corrections (0081 §5-§7, §9) are a sibling issue, not this unit.

**Stubs on master**: none. The shapes are named in Composition, and the drone adds them.

```drift-stamp bd800181
systems/turn_manager.gd:27-30 — the world_turn_ended signal and its N wording
systems/turn_manager.gd:95-109 — world_turn_progress, the >= rule, resync adoption
systems/turn_manager.gd:384-409 — the counter compare and _end_world_turn's order
combat/combat_world.gd:175-218 — the _lingering registry: the index's template, live-only
combat/node_combat.gd:768-775 — the host != null guard that keeps shadows out
effects/status/spread/fraction_diffusion.gd:1-27 — the existing floored Metropolis on rows (not reused)
docs/design/elements.md:209-215 — cooling: decay 1 toward zero per world turn, the dead band
docs/design/elements.md:693-703 — one snapshot per beat, summed and clamped: the shared routine
docs/design/elements.md:728-742 — two clocks; the settle is roll-free and reproduced
docs/design/elements.md:891-941 — one signed t, the Metropolis rule, the world clock, the build note
docs/adr/0055-turnless-hosts-tick-on-the-world-turn-one-every-n-played-turn-ends.md:30-42 — the linear-N decision; stands as the default
docs/domain/rounding.md:13-30 — the table a new rounding site joins first
docs/domain/degree.md:8-21 — get_graph_degree, never get_neighbours().size()
.mise/tasks/lint-transcendentals — the ban; sqrt allowed, still unused here
docs/domain/multiplayer-sync-model.md:105-107 — the obligation already names the world-turn settle
systems/turn_manager.gd — seam: clock, knobs, the pass call
combat/combat_world.gd — seam: index owner and flow_temperature
test/unit/systems/test_world_turn.gd — seam: linear-N pins stay as-is; new CEIL_SQRT cases
test/unit/systems/test_turnless_tick.gd — seam: turnless hosts ride the clock
test/unit/effects/test_status_linger.gd — seam: lingering rows ride the clock
test/unit/network/test_turn_cursor_crosses.gd — seam: world_turn_progress crosses the cursor
network/entity_snapshot.gd — seam: cursor carries world_turn_progress (unchanged shape)
docs/domain/status-effects.md — seam: the clock sentence at 43-46
docs/domain/turn-manager.md — seam: world_progress wording
```
