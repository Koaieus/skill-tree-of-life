# Audit — `test/` infrastructure (189 `.gd`, 27,188 lines)

Scope: helpers, fixtures, doubles, base classes, `.gutconfig.json`, suite shape.
Not individual assertions.

---

### 1. LARGE | test/unit/**/*.gd:1 | No fixture layer; 44 tests rebuild the world

**Defect:** 186 of 189 scripts `extends GutTest` bare with zero shared base or
builder — 44 files preload `graph.tscn` + `skill_node.tscn` +
`default_entity_board.tres` together and re-open the identical `before_each`
(`_graph = _GRAPH_SCENE.instantiate()` / `add_child_autofree` / `"N%d" % i` loop
×22 / `"TestGraph"` ×24), 37 of them also hand-building `AllocationSystem.new()`.
**Breaks:** any signature change on `Graph`, `Entity`, `SkillNode` or
`EntityStatBoard` construction is a 44-to-77-file edit, which is precisely why
`skill_node.gd` has 34 commits in 3 weeks and no one refactors it; the local
helpers `_make_entity` (18 copies), `_add_edge` (18), `_make_node` (7), `_board`
(7) drift apart silently.
**Fix:** promote the two fixtures that already exist and work —
`test/unit/spell/spell_test_helper.gd` (`class_name`'d `RefCounted` taking
`gut: GutTest` so it can call `add_child_autofree`) and
`tools/balance/balance_fixture.gd` — into `test/unit/_fixtures/world_fixture.gd`
with `make_graph(adjacency)` / `make_entity()` / `make_systems()`, and migrate
the 44 en masse; prefer this over a `TestCase extends GutTest` base because GUT
collects on the `test_` filename prefix, so a non-`test_`-prefixed helper file
already coexists in `test/unit/` uncollected (proven by `spell_test_helper.gd`
and `vfx/stub_never_finish_visual.gd`) whereas a base class forces every script
to change its `extends` line to gain anything.

### 2. LARGE | (repo root) | Nothing gates the suite; the process pre-authorizes red

**Defect:** there is no `.github/` at all, no git hook, and `mise run test` is
invoked only by prose in skill files — so master went red and no mechanical step
could notice.
**Breaks:** 6 failures across 4 scripts sit on clean HEAD; `drone/SKILL.md:129`
tells workers not to over-verify and `:135` tells them a suspected pre-existing
failure goes in `NOTES:` for someone else to confirm, so a red suite is
*expected* to be handed onward, and FOCUS lane E item 7 parks a known-broken
`test_fan_scene` in the collected suite rather than quarantining it — the suite's
signal value is now zero, because every new failure is indistinguishable from the
6 standing ones.
**Fix:** add a CI workflow (or at minimum a `pre-push` hook) running
`mise run check && mise run test`, and mark the 4 known-broken tests
`pending("#362 / #<n>")` today so the baseline is green and any *new* red is
unambiguous — GUT's `pending()` is currently used zero times in the suite
(the 7 grep hits are a production `PoolLevelSequencer.pending()` API).

### 3. LARGE | stats_system/stat.gd:89 | Board↔Stat cycle leaks every duplicated board

**Defect:** `StatBoard` holds `Stat`s by `@export`, `Stat._board: StatBoard` holds
the board back by strong ref (and mirrors it again onto `Stat.bins.board`,
`modifier_bins.gd:34`) — a `RefCounted` cycle that refcounting cannot collect,
formed on the first `add_modifier` call.
**Breaks:** 77 test files call `default_entity_board.tres.duplicate(true)`, most
per-`before_each`, across 1,449 tests; nothing in the suite frees a board and
nothing asserts an ObjectDB/orphan count, so the reported 133,993 leaked
instances grow invisibly — consistent with this mechanism, though I could not
measure the attribution (read-only, no suite run permitted). Leaked live
`Stat`s stay connected to `value_changed` and to `Events`, which is a real
order-dependence hazard, not just memory.
**Fix:** the cycle itself is `audit-stats`' call (`WeakRef` on `_board`, or an
explicit `StatBoard.dispose()`); the infra half is a fixture that owns board
teardown plus one `test_no_orphans.gd` asserting the ObjectDB delta across a
representative `before_each`/`after_each` pair, so the number can never silently
climb again.

### 4. MEDIUM | tools/balance/balance_fixture.gd:1 | The real fixture lives in prod, used once

**Defect:** `BalanceFixture` builds Graph + Entity + AllocationSystem + a
CHAIN/TREE topology through real production paths — exactly the seam finding 1
wants — but it sits in shipped `tools/` and exactly one test
(`test_balance_harness.gd`) consumes it.
**Breaks:** the suite ships two disjoint half-fixtures (`SpellTestHelper` for
spell resolution, `BalanceFixture` for levelled territory) and 44 hand-rolls,
none of which can be improved once for everyone; and because it lives in `tools/`
it is compiled into release builds for a test-only purpose.
**Fix:** move it under `test/unit/_fixtures/` and make it the topology backend of
the unified fixture from finding 1.

### 5. MEDIUM | tools/balance/balance_fixture.gd:67 | Fixture adds children without autofree

**Defect:** `root.add_child(fx.graph)` (:67), `fx.graph.add_child(fx.entity)`
(:73) and `root.add_child(fx.alloc)` (:78) are plain `add_child` — the fixture
constructs a whole world per call and frees none of it.
**Breaks:** this is the leak pattern at fixture level rather than test level, and
it is the version that gets copied: 54 test files contain a `.new()` /
`.instantiate()` and no `autofree` anywhere in the file, and only 20 of 189
scripts define `after_each` at all.
**Fix:** take the `gut: GutTest` handle the way `SpellTestHelper.make_graph`
does and route every child through `add_child_autofree`.

### 6. MEDIUM | test/unit/ | Half-migrated layout hides the coverage question

**Defect:** 127 scripts sit flat in `test/unit/` alongside seven subject
subdirectories (`attack/ entity/ procgen/ spell/ systems/ ui/ vfx/`), and the
split is not by subject — `test_vision_system.gd` is in `systems/` but
`test_staking.gd`, `test_entity_death.gd` and `test_edge_mesh_render.gd` are
flat.
**Breaks:** "does subsystem X have tests?" is unanswerable by looking, which is
how #357/#358/#359 and #284 can each claim a gap without anyone resolving it;
the mirror-the-source convention that would make gaps self-evident is started and
abandoned.
**Fix:** finish the migration — one test dir per source dir, flat file count
zero — and adopt it as a rule so new tests land in the right place.

### 7. MEDIUM | attack/, graph/ | Confirmed dead zones: no test names these files

**Defect:** no test script mentions `attack/range_finder/hop_range_finder.gd`,
`euclidean_range_finder.gd`, `range_visual.gd`, `attack/targeting/node_targeting.gd`,
`graph/graph_mirror.gd`, `graph/astar_skill_tree.gd`, or four propagation filters
(`core_distance_filter`, `expression_filter`, `max_visits_filter`,
`owner_filter` — the last only reached indirectly via `SpellTestHelper.owner_enemy()`).
**Breaks:** #284 (targeting + range-finder) and #358 (propagation filters) are
confirmed real, not speculative; `graph_mirror.gd` is untested despite being the
`get_degree` authority the degree rule routes everyone to, and
`astar_skill_tree.gd` backs every pathfinding query in the game.
**Fix:** the whole-file gaps above are the coverage backlog — file them against
the existing issues rather than re-deriving; range-finders and filters are pure
functions and cost a few tests each.

### 8. MEDIUM | test/unit/*.gd | 42 tests hand-wire what game_root.tscn composes

**Defect:** `AllocationSystem.new()` in 42 files, `BattleSystem.new()` in 11,
`TurnManager.new()` in 9, each followed by manual `.graph = `/`.turn_manager = `
assignment; production wires all of these as exported NodePaths in
`scenes/game_root.tscn:36-88`, and only 3 tests touch `game_root.tscn`.
**Breaks:** this violates `.claude/rules/scene-composition.md` at 62 sites, and
worse it means the composition root's wiring is untested — a NodePath that goes
stale in `game_root.tscn` breaks the game while the suite stays green, and a
newly required dependency breaks 42 tests that a scene edit would have covered.
**Fix:** have the fixture instantiate `game_root.tscn` (or a trimmed
`test_game_root.tscn` inherited from it) so tests consume the real composition
and a scene rewire is caught once.

### 9. MEDIUM | test/unit/test_ai_controller_combat.gd:145 | 43 wall-clock sleeps in the suite

**Defect:** 43 `await get_tree().create_timer(0.3).timeout` calls (concentrated in
`test_ai_controller_combat.gd` and `test_ai_controller.gd`) gate assertions on
real elapsed time rather than on a signal or a frame count.
**Breaks:** these are the classic order-dependent failures — they pass on an idle
machine and fail under a loaded CI runner or alongside a slow neighbour, and they
cost ~13s of a ~28s suite; they also make the 6 standing failures harder to
attribute, since a timing flake and a logic break look identical.
**Fix:** `await` the actual completion signal (`Events.*`, tween `finished`), or
drive N `process_frame`s with an explicit delta.

### 10. MEDIUM | test/unit/ui/*.gd | 470 assertions reach into private state

**Defect:** 470 `obj._private` accesses across the suite, concentrated in
`ui/test_fan_trace.gd` (38), `ui/test_tooltip_fan.gd` (26),
`ui/test_tooltip_fan_components.gd` (26), `attack/test_click_grammar.gd` (25),
`ui/test_loot_picker.gd` (23).
**Breaks:** these tests pin implementation, not contract — #380's
inherited-panel-scene refactor of the tooltip fan has to rewrite ~90 assertions
that describe how the old code stored things, which is a direct tax on the
refactor FOCUS lane E already wants; and the tests give no signal that the
public behaviour survived.
**Fix:** where a test needs private state, that state usually wants a public
read-only accessor on the production class; add it there rather than reaching in.

### 11. MEDIUM | test/unit/test_node_visuals_panel.gd:21 | Hardcoded deep node paths

**Defect:** 71 string/`$` node-path lookups, including full chains like
`get_node("ViewportContainer/World/LabSlot/SkillNodeLab")` (×3 in one file),
`get_node("Entities/Attacker")`, `get_node("Visuals/HealthBar")`.
**Breaks:** renaming or reparenting a node inside a scene — routine during the
sandbox-host and tooltip-fan refactors both in flight — makes these fail with
"node not found" rather than a behavioural message, and the deep-chain ones break
on any intermediate rename the test does not care about.
**Fix:** use `%UniqueName` (already the project convention per CLAUDE.md, and
`ui/test_xp_track_level_sequence.gd` does it correctly) or an exported reference.

### 12. MEDIUM | .gutconfig.json:1 | Config has no pre-run hook and excludes test/perf

**Defect:** `dirs` is `["res://test/unit/"]` only; there is no `pre_run_script`
where a global seed / orphan-baseline / autoload reset could live, and
`log_level: 1` suppresses the per-test detail that would identify which script
leaked.
**Breaks:** every cross-cutting concern (RNG seeding — 67 sites do it
per-file; orphan counting; `Events` bus reset) has to be re-solved per script
or not at all; `test/perf/bench_blade_sim.gd` is collected by nothing and
runnable only from a docstring in `docs/domain/melee-blade-sim.md`.
**Fix:** add a `pre_run_script` that seeds RNG once and snapshots the ObjectDB
baseline, and add a `mise run bench` task so the perf script is discoverable.

### 13. NIT | test/unit/**/*.gd | 199 exact-float `assert_eq` sites

**Defect:** 199 `assert_eq(x, <decimal literal>)` calls sit alongside 527 correct
`assert_almost_eq` uses.
**Breaks:** the stat pipeline multiplies through `(1 + Σ INCREASE/100) × Π
MULTIPLY`, so a retune that changes evaluation *order* without changing the
mathematical result flips these to red for no real reason — #278's INT-coefficient
retune is exactly that shape.
**Fix:** sweep the 199 to `assert_almost_eq` except where the value is provably
integral.

### 14. NIT | test/unit/attack/, test/unit/procgen/ | Test count wildly off source size

**Defect:** `attack/` is 80 source files with 5 tests in `test/unit/attack/`
(plus 10 in `test/unit/spell/`); `procgen/` is 47 source files with 1 test in
`test/unit/procgen/` (10 more are flat `test_procgen_*.gd`, per finding 6);
`graph/` is 5 core files with no `test/unit/graph/` directory at all.
**Breaks:** confirms #357/#359 from the tree shape — the non-melee attack path
and the graph layer are the two thinnest slices relative to their centrality.
**Fix:** once finding 6's layout migration lands, this ratio becomes a
maintainable at-a-glance metric; until then it is invisible.

### 15. NIT | test/unit/test_pool_seed_values.gd:14 | Four tests hold shared `.tres` undoubled

**Defect:** `specimen_pool_set.tres`, `balanced_core.tres` and
`factions/player.tres` are preloaded as `const` in four files with no
`.duplicate()` anywhere in the file.
**Breaks:** Godot caches resource loads process-wide, so any future in-place
write to one of these poisons every later test in the run — an order-dependent
failure with no local evidence. Currently these four only *read*, so this is a
latent trap, not a live bug; notably all 77 `default_entity_board.tres`
consumers do duplicate correctly, so the convention exists and these are the
gaps.
**Fix:** duplicate on read in the fixture, so no test ever holds a live handle
to a shared authored resource.

---

## Verdict

The test suite is a large body of individually careful tests with essentially no
infrastructure underneath them: two half-fixtures (one stranded in `tools/`), one
stub, no base class, and 44 hand-rolled world builders that are copies of each
other down to the string literals. That single absence explains most of the
other findings — the leak, the untested composition root, the coverage blind
spots, and the tax any `Graph`/`Entity`/`SkillNode` refactor pays. The process
gap is separate and cheaper to fix: nothing mechanically runs the suite, and the
drone workflow explicitly permits passing a red suite along, so master went red
and stayed red with a known-broken test left collected rather than quarantined.
Unifying the fixture and adding a CI gate are the two changes that make every
other finding tractable; done in that order, the coverage gaps in `graph/`,
`attack/range_finder/` and the propagation filters become cheap to close.
