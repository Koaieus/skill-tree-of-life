# Stat board classes — the #332 three-class split

Why `StatBoard` holds no stats, why `EntityStatBoard` and `NodeStatBoard` are
siblings rather than a chain, and why node boards bake some stats and stay
sparse for the rest. The one-screen version lives in
`.claude/rules/stats-system.md` under "Board classes"; this is the reasoning and
the measurements behind it.

## Three board classes: mechanism base + Entity/Node siblings (#332)

`StatBoard` holds **no stat fields at all** — it is lookup, modifier routing, binding, the cycle gate, and the introspection walks. Two **siblings** carry the stats:

| Class | Holds |
|---|---|
| `EntityStatBoard` | every stat an entity can possess, as typed `@export` fields (`entity/default_entity_board.tres`) |
| `NodeStatBoard` | node-**owned** stats baked as typed fields (`skill_node/default_node_board.tres`); borrowed ones sparse |

**Siblings, not a chain.** A node board is not a specialization of an entity board; inheriting ~40 permanently-null entity fields onto every one of a level's 500–2500 SkillNodes is the shape the split exists to avoid. The base keeps the name `StatBoard`, so every function taking a board (`StatFormula.compute`, `Mitigation.apply`, the visualizer, `SkillNode._contribution_board`) is unchanged and polymorphic.

**Why inheritance and not an array of sub-boards.** The existing mechanism *is* `get_property_list()` introspection — `collect_formula_edges`, `get_pool_stats` and `get_stat_ids` discover a subclass's fields for free. Sub-boards would mean reimplementing discovery in `get_stat`, both walks, `bind_modifier`/`unbind_modifier` and `stat_board_graph.load_board`, and their one upside (authoring a shared group once) does not apply: node boards resolve shared ids dynamically through `StatRegistry`, never as fields.

### `_mint_stat` is the subclass seam; `_ensure_stat` is the gate above it

`_ensure_stat` owns the accessor-token rejection and the already-exists short-circuit, then delegates to `_mint_stat(id)` — so no subclass can forget the gate.

- `StatBoard._mint_stat` — mints from `StatRegistry` into `_extra_stats` (the sparse default).
- `EntityStatBoard._mint_stat` — **refuses, with a warning.** An entity board declares every stat it can hold, so a mint attempt is a typo in a modifier's `stat_id` (or a node-only id aimed at the wrong board). The rule is derived from the class shape, **not an authored deny-list**, so it cannot drift.
- `NodeStatBoard._mint_stat` — one exception: `node_health` becomes a **`PoolStat` built from the `node_combat_health` def**, because the entity board's `node_health` is the ScalarStat *baseline*. Same id, different Stat class per board. This used to be a hardcoded branch in `SkillNode._ensure_local_stat` writing straight into `node_board._extra_stats`.

**No mirror guard on `NodeStatBoard`, deliberately.** An entity-only stat minted on a node board is *inert*, not wrong (a node-local `strength` modifier is simply never read), and rejecting it would require authoring "stats that mean nothing on a node" — a design statement (#287's `StatDef` scope enum), not a mechanism. Both leak directions are equally harmless; only the entity one is free to close.

### Bake what the node owns; stay sparse for what it borrows

This line is **forced by the read path**, not chosen for taste. `get_local_value` merges an owned node as `ModifierBins.compute(entity_stat.base_value, [entity.bins, node.bins])` — for any id the entity *also* carries, the node-board stat's own `base_value` is **silently discarded** and only its bins count. Authoring `armor = 5` on a node board does nothing, with no error.

- **Owned** (nothing on the entity board shadows the id): `stake_level` (PoolStat, cap = stake / current = allocation level) and `addon_slots`. Baked as typed fields with live authored `base_value`, plus the `addon_slots = base(0) + allocation_level` formula as a template **intrinsic** (`node_board.apply_intrinsics()` runs in `SkillNode._init_node_board`). Nothing is built in code any more — `_mint_stake_pool` / `_mint_addon_slots` are gone.
- **Borrowed** (`armor`, `min_damage_taken`, `node_healing`, `blade_damage`, `node_health`, …): mint-on-demand. Nothing to author, so a field would buy nothing and cost one Stat per node. `node_health` is on this side despite being the node's own combat pool — the entity carries that id as the baseline, so it is shadowed.

### `get_stat_ids()` vs `get_dynamic_stat_ids()` — promoting a stat to a field drops it from the latter

`get_dynamic_stat_ids()` reads `_extra_stats` **only**. So baking a stat silently removes it from that answer, and `ui/tooltip_fan/panels/node_stats_panel.gd` enumerated the node board through exactly it. `get_stat_ids()` (non-null typed fields **plus** minted ones) is what a "what's on this board" UI wants. Use it for display; `get_dynamic_stat_ids()` only when you specifically mean "what got minted" (the sparseness assertions in `test_node_local_bind.gd` / `test_addon_slots.gd` do).

### `SkillNode.node_board` is `@export`ed, scene-composable, and cloned once

`_init_node_board()` deep-clones the authored board (the scene wires `default_node_board.tres`) or the template, exactly like `Entity._ready`. Lazy — a node that needs nothing never pays for a clone.

**Exporting it is safe, and the earlier reasoning against it was wrong.** The derived-value-writeback hazard needs a *transforming* function: the editor serializes the computed value, the next load computes again from there, and it compounds. `duplicate(true)` is **idempotent** — a deep copy round-trips to the same values — so writing the clone back into the export is stable. `Entity` has always done this, and `dev_sandbox.tscn` carries two fully-authored inline entity boards as proof. A level, cluster or single node should be able to compose its own board, and a saved level should serialize real per-node stat state.

**Deep clone, not `resource_local_to_scene` on the template.** That flag does **not recurse into sub-resources**; each baked Stat would need it individually, or every SkillNode in the level would share one set of Stat instances and every local modifier would apply globally. The Entity pattern has no such discipline to remember.

**The real hazard is conflating *authored* with *initialized*.** `if node_board != null: return` means a scene-authored board never gets `apply_intrinsics()` — a correct-looking board with a dead `addon_slots` formula and no error anywhere. `_node_board_ready` is the initialization flag; `node_board`'s setter resets it, because assigning the property means "here is the authored board" and must force a re-clone. That also keeps `fan_live_sandbox.gd`'s `node_board = null` idiom working for a board-less node. Every read path gates on the flag, never on non-null — otherwise it would read or mutate the *shared* authored template, which is reachable now that the scene wires one.

**Measured cost at level scale (2500 nodes, CPU-bound):** old mint path 19.5 ms, new clone path 158 ms — **+139 ms** one-time at generation. Breakdown at the time: `duplicate(true)` 56 ms, `apply_intrinsics` 89 ms, pushes 14 ms. This is a **worst case**: the bench forces `_init_node_board()` on all 2500, whereas the board is lazy and only materializes for nodes that actually take a local modifier or get allocated. (Baseline — don't re-derive it; the #402 re-measurement below is on top of it.)

The `addon_slots` formula is **file-backed** (`stats_system/formulas/allocation_scaling.tres`), not inline, so `duplicate(true)` shares one instance across every board instead of forking the curve 2500 ways — the `level_scaling.tres` contract, pinned by `test_allocation_scaling_formula_is_shared_across_every_node_board`. Inlining it cost ~7 ms of the duplicate term and would have broken shared retuning silently. The **modifier** stays inline/per-board on purpose: it is the reactive subscriber, and one shared instance would make a single node's allocation change recompute `addon_slots` on every node in the level.

**#402 — `get_property_list()` walk cached per board class.** The dominant term inside `apply_intrinsics` used to be `cycle_from` → `collect_formula_edges` → `get_property_list()`, 27 ms of it in `get_property_list()` alone (~11 µs per call, purely to enumerate properties) — and `get_pool_stats` / `get_stat_ids` paid the same walk on every call. `StatBoard._stat_property_names()` now caches the declared Stat-typed field names in a `static var`, keyed by `get_script()` (a board *class* fact — see its docstring for why the cache key can't be "which fields are non-null on the first instance seen"). Re-measured on the same 2500-node bench: `duplicate(true)` 51.5 ms (unaffected, as expected), `apply_intrinsics` 89 ms → **44.4 ms**, roughly halved. `get_pool_stats`/`get_stat_ids` get the same win for free since they now share `_stat_property_names()` too, though they weren't on this bench's hot path.


### Cloning a *live* board (`clone_live`) — what it costs and what it can't carry

`duplicate(true)` clones a **virgin template**; `StatBoard.clone_live()` clones an
already-modified board. The distinction went unnoticed until #498's combat shadow
needed the second one — every pre-#498 caller (`Entity._ready`,
`_init_node_board`, `EffectContext.grant`) clones a template and builds it up
afterwards. Exports-only means every `Stat.bins` comes back empty and
`_extra_stats` (every minted stat, `node_health` among them) is gone outright,
with no error on any path.

**A bin tally is only meaningful next to the `_modifiers` list it was folded
from.** `Stat.add_modifier` ends in `_resync_bins_if_trivial()`, which wipes the
bins and rebuilds them from `_modifiers` whenever that list holds 0 or 1 entries.
So `clone_live`'s original bins-only copy produced a board that was correct
*until someone mutated it*: the first modifier added threw the whole tally away
(measured: 40 STR → 20 after a +10), and removal mis-subtracted the same way.
Fixed in `1f95076` — `Stat.adopt_modifier_list(src)` carries `_modifiers` and
`_last_contrib` one level deep, the same shared-instance rule
`bins.multipliers` already followed (safe per #377: a modifier is stateless and
may live on N boards). Pinned by `test/unit/test_stat_board_clone_live.gd`.

**A clone reacts — but only via per-clone copies of the formula-bearing
modifiers (#506).** Formula binding is per-board signal wiring `duplicate()`
cannot carry, and rebuilding it by calling `bind_modifier` on each *applied*
modifier is **wrong, not merely missing**: the modifiers are shared instances, so
the clone's `value_changed` would `emit_changed()` on an instance the **live**
board is also subscribed to (a shadow firing recomputes and notification storms
on the real world, exactly what #498 exists to prevent), and the connected
`Callable` holds a strong reference that keeps every shadow `Stat` alive for as
long as the shared modifier does — and because that anchor belongs to the *live*
board, no shadow teardown could ever undo it.

Both fall away once the modifier is the clone's own. So `clone_live` sets
`StatBoard._is_clone`, and from then on every formula-bearing modifier admitted
to that board is replaced by a private copy first — at clone time by
`Stat.localize_formula_modifiers`, and afterwards by `add_modifier`, so a
modifier granted *during* a simulation (an `AuraEffect` recompute against a
shadow) is localized on the way in too. The whole `source stat → modifier →
target stat` chain then belongs to one board.

Four consequences:

- **Static modifiers stay shared and unsubscribed.** They have no source to
  watch, so a clone does not track later `value` edits to the live statics it
  borrowed. Deliberate: a shadow is a frozen world plus its own mutations, and
  copying all N modifiers to hear about edits nobody makes mid-rollout would pay
  exactly the cost measured below.
- **Removal is by identity, so `StatBoard._localized` maps `original → copy`**
  and `remove_modifier` translates through it. That keeps the stated contract
  that *the handle a caller already holds is the handle that works* — the case
  #498 step 3's forced-dealloc cascade needs, where the revoker only ever held
  the live instance. Aliases chain, so an original still resolves on a clone of
  a clone.
- **Localizing must run after the whole ensure/copy pass, never inline.**
  `bind_modifier` resolves each formula input through `dst.get_stat(id)`; a
  source stat the clone has not minted yet yields a `push_warning` and a
  silently absent binding. The named `constitution → node_health` case happens
  to survive one-pass (CON is a typed field), which is what makes the bug easy
  to ship.
- **`Stat._modifiers` is swapped everywhere it is keyed by identity** —
  `_modifiers`, `_last_contrib`, `bins.multipliers`, `bins.winning_set`. Missing
  one does not give a wrong value (the pipeline resolves against `bins.board`
  either way); it gives a modifier that cannot be revoked, which is worse for
  being invisible.

**Reactivity costs ~40% on the clone itself**, measured the same way as the table
below: entity board `clone_live` 507 → ~710 µs, node board 33 → ~45 µs. All of it
is `StatModifier.duplicate()` plus the bind walk — the entity board's ~13 formula
intrinsics. Hand-copying the five exported fields instead of `duplicate()`
recovers only ~20% of that and silently drops any field a `StatModifier` subclass
adds, so it was measured and rejected.

**End to end it costs much less than that**, because #514's `release()` landed in
the same change: one 200-owned `snapshot()` + `free_shadow()` went 9.9 → 12.8 ms
with reactivity alone, then back to **~10.9 ms** once the shadow's boards are
actually collected instead of stranded. Net ≈ +9% (1.43 → ~1.57 frames @144Hz),
stable across runs. Reactivity is not free, but the leak was costing more than it
was saving.

### A dropped clone is never collected — `release()` is not optional (#514)

Predates #506; found while measuring it. Over 200 `clone_live()` calls on
`default_entity_board`, each result dropped, sampling
`Performance.OBJECT_COUNT`: **108 objects leaked per clone before #506, 122
after, 0 with `release()`.**

The cycle is `StatBoard` → its `Stat`s → `Stat._board` / `bins.board` → back to
the board, and `RefCounted` has no cycle collector — the same class of cycle
`EntityCombat.free_shadow()` already existed to break for `NodeCombat._owner`,
one layer down. It is **not** the localized modifiers' `changed` connections:
disconnecting every one of those and leaving the backpointers moves the number
not at all (122 → 122), while nulling `_board` / `bins.board` drops it to
exactly 0 and collects the modifier copies along with everything else.

So `StatBoard.release()` nulls those two fields across the board's stats, and
`EntityCombat.free_shadow()` calls it for the entity board **and every owned
node's board** — before it clears `_owned`, which is the only order that can
still reach them. Not a call a caller could forget, for the same reason the
mirror free isn't.

Two properties worth keeping:

- **It refuses a live board.** An `Entity`'s board is freed with the entity;
  unwiring one would silently break batching, composed reads, and every formula
  chain on it.
- **A released board is inert, not blank.** `release()` also unbinds the
  localized copies and drops each stat's modifier subscriptions — not needed for
  collection (measured), but a board nobody may read should not still be wired
  to fire recomputes. `_modifiers` and `bins` are deliberately left alone;
  clearing the list would trip `_resync_bins_if_trivial`'s wipe for no reason.

**The cost is `Resource.duplicate(true)`, and nothing else.** Measured
2026-08-21, `test/perf/bench_combat_snapshot.gd`, real `first_level.tres` procgen
at 2000 nodes, seed `0x57A17EE`, RX 7900 XTX box, headless:

| | `duplicate(true)` | `_ensure_stat` re-mint | whole `clone_live` |
|---|---|---|---|
| entity board | 419 µs | — | 420 µs |
| node board (median of 200 owned) | 25 µs | 6 µs | 31 µs |

**The bin copy does not register against a microsecond timer** on either class —
the incremental-tally design doing exactly what `modifier_bins.gd` claims: a
clone copies the fold, it never replays the modifiers. So "copy the bins more
cleverly" is not an available optimisation; there is nothing there to optimise.
What that adds up to for `EntityCombat.snapshot()` (one entity board + one node
board per owned node + a `GraphMirror` add each):

```
owned | snapshot+free (med) | board clones only | us/node | frames @144Hz
   10 |            1255 us  |           1017 us |   125.5 |         0.18
   50 |            2849 us  |           2431 us |    57.0 |         0.41
  100 |            4968 us  |           4368 us |    49.7 |         0.72
  200 |           10194 us  |           8454 us |    51.0 |         1.47
```

One snapshot at 200 owned is 1.5 frames of the whole 144Hz budget, ~83% of it
board cloning. Affordable for melee (`AiBladeRollout` promotes 3 finalists);
**not** affordable for the exhaustive ranged/magic candidate enumeration that
#498 exists to make gate-accurate. The lever, if it bites: `ModifierBins.compute`
is already N-source, so a slice can compose `[live.bins, …, overlay.bins]` and
copy nothing at all — see the #498 comment of 2026-08-21.
