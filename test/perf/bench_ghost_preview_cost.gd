extends GutTest

## #681: what [method MagicAttackPlan._rebuild_preview] costs, once per
## PREVIEW-TARGET CHANGE (not per repaint — see [member MagicAttackPlan._preview_dirty]),
## on a real `first_level.tres` level at its shipped 800-node scale.
##
## Run: [code]mise run test:one -- res://test/perf/bench_ghost_preview_cost.gd[/code]
##
## [b]Not collected by the suite[/b] — same double opt-out as its siblings:
## `test/perf/` is outside `.gutconfig.json`'s `test/unit/`, and `bench_` keeps
## even `test:dir` from finding it.
##
## [b]Two axes, not one — the second only showed up once numbers came back.[/b]
## The original theory here was "sweep TARGET, not owned count": [method
## MagicAttackPlan._edge_lookup] walks the WHOLE graph's edges (O(total
## edges), independent of territory) and [method SpellResolver.resolve]'s
## propagation walk is hop-bounded, not owned-count-bounded — both still true.
## But the first run showed ~18ms flat across targets whose walk visited 2 to
## 8 nodes, which is the signature of a term that ISN'T the walk. It is
## [method CombatWorld.combat_for]: the shadow world snapshots an [b]entire[/b]
## touched entity's board — one [EntityCombat] `snapshot()`, O(that entity's
## owned-node count) per `bench_combat_snapshot.gd`'s own header — the first
## time ANY of its nodes is touched, and [method MagicAttackPlan._rebuild_preview]
## mints a FRESH [CombatWorld] every call, so that full-board snapshot is repaid
## from scratch on every single hover change, however small the walk. So this
## bench ramps DEFENDER OWNED COUNT after all — not because the walk or the
## edge lookup scale with it, but because the shadow snapshot hiding inside
## [method SpellResolver.resolve] does.
##
## [b]Spell: Trail Blazer.[/b] Named explicitly in #679/#385 as the shape that
## matters — "Trail Blazer's now-unbounded string walk" — because its
## propagation has no distance-from-source cap of its own; termination comes
## only from hitting a degree>2 junction. If any shipped spell's preview is
## going to show up on this bench, it is this one.
##
## [b]Fixture shape.[/b] Real `first_level.tres` procgen, UNMODIFIED node count
## (the shipped 800, not the 2000 "North Star" override the allocation/vision/
## snapshot benches use — #681 asks for the number at the level this preview
## actually ships on). One random AI starter gives a defender core; the
## defender grows a real chunk of territory via the same [AllocationPolicy]
## the game uses; the attacker's source is planted directly on the frontier —
## an unclaimed node neighbouring defender territory — so the hover sweep has
## a realistic spread of in-range hostile targets instead of an empty set.
## The attacker itself owns only its single frontline node throughout: this
## measures the cost driven by the DEFENDER's board, in isolation, and is
## therefore a floor — a real mid-game attacker with its own hundred-plus
## owned nodes pays an attacker-side snapshot on top of this the moment the
## walk (or a future spell) touches one of ITS own nodes too.
##
## Numbers move with the machine — record the CPU alongside any result you cite.
##
## [b]First run, 2026-08-31[/b] (RX 7900 XTX box, headless). 800 nodes, 1236
## edges. `_edge_lookup` is flat and cheap regardless of territory, exactly as
## predicted — the ramp is entirely someone else's:
## [codeblock]
## defender owned | _edge_lookup (med) | _rebuild_preview (med) | worst   | frames @144Hz (worst)
##              50 |             1927 us |             7938 us |   8864 us |  1.28
##             100 |             1849 us |            12595 us |  13660 us |  1.97
##             200 |             2010 us |            22350 us |  23996 us |  3.46
## [/codeblock]
## Attribution at 200 defender-owned, one candidate (`test_shadow_world_lifecycle_attribution`):
## [codeblock]
## CombatWorld.shadow() mint            5 us ( 0.0%)
## SpellResolver.resolve_against    17862 us (83.9%)  <- walk + lazy full-board snapshot
## world.free_shadow()               3432 us (16.1%)
## total                            21299 us
## [/codeblock]
## [b]Verdict: OVER BUDGET, and the issue's own proposed mitigation (debounce)
## cannot fix it.[/b] A single `_rebuild_preview` call already costs 1.28x to
## 3.46x the whole 144Hz frame budget BEFORE any sweep — debounce collapses N
## resolves-per-frame to 1, and 1 is already too slow. The cost tracks
## DEFENDER owned count near-linearly (50->200 owned is 4x territory, 2.7x
## `_rebuild_preview` cost), which is `CombatWorld.combat_for`'s lazy
## `EntityCombat.snapshot()`: the first touch of ANY node owned by an entity
## snapshots that entity's WHOLE board (see `bench_combat_snapshot.gd`), and
## because [method MagicAttackPlan._rebuild_preview] mints a brand new
## [CombatWorld] on every call, that full-board cost is paid again from
## scratch on every single hover change, however small the actual propagation
## walk. `resolve_against` (walk + snapshot, inseparable from outside
## [CombatWorld]) is 84% of the total; `free_shadow` (releasing every cloned
## board) is another 16%; minting the empty world itself is noise. This is
## the same mechanism #537 already named for AI candidate scoring, now
## measured directly on the player-facing hover path it was filed to check.
## Not something a one-frame debounce, or a (source, target, spell) cache with
## a sweep's poor hit rate, resolves — the shape of a fix is a preview path
## that reads node/entity state without a full defensive-copy snapshot per
## hover, which is a `CombatWorld`/`SpellResolver` change, out of scope for
## this measurement bench. See #681 for the follow-up decision.
##
## [b]Fixed by #695, 2026-09-03[/b] (same box, headless, same fixture): the
## shadow now mints one [NodeStatBoard] per node the walk actually TOUCHES
## ([method EntityCombat.shadow_for]) instead of one per node the defender owns,
## and materializes the rest only when something entity-wide (a cascade) needs
## the set. The ramp is gone — what is left is the flat `_edge_lookup` term plus
## one entity-board clone and the owned-set mirror build:
## [codeblock]
## defender owned | _edge_lookup (med) | _rebuild_preview (med) | worst   | frames @144Hz (worst)
##              50 |             1812 us |             4273 us |   4960 us |  0.71
##             100 |             1817 us |             4656 us |   5144 us |  0.74
##             200 |             1741 us |             5346 us |   6021 us |  0.87
## [/codeblock]
## Attribution at 200 defender-owned, one candidate: resolve_against 2896 us
## (was 14920), free_shadow 458 us (was 2432), total 3357 us (was 17355) — a
## 5.2x drop on the lifecycle. The remaining shallow ramp (~7 us per owned
## node) is the `mirror_add` per owned node the snapshot still does eagerly;
## the assert below keeps the 2x-budget line as the regression catch for the
## whole-subgraph clone coming back (2.79x measured just before the fix).

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")
const _TRAIL_BLAZER := preload("res://attack/spell/defs/trail_blazer.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

const _FRAME_BUDGET_USEC := 6944.0   ## 144Hz, the North Star.
const _SEED := 0x57A17EE
const _DEFENDER_CHECKPOINTS: Array[int] = [50, 100, 200]
const _MAX_FRONTIER_SEARCH := 400   ## give up growing the attacker's foothold search this far
const _SAMPLES_PER_TARGET := 3
const _TARGETS_SAMPLED_PER_CHECKPOINT := 6   ## cap the hover sweep — the ramp already pays 3 checkpoints

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _plan: MagicAttackPlan
var _policy: AllocationPolicy
var _built := false


func _ensure_fixture() -> void:
	if _built:
		return
	_built = true

	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.seed = _SEED
	# One AI starter for the defender's core — the shipped level's own
	# `CenterCoreStarters` sized off a real roster's `camp_sizes` would let AI
	# territory grow unpredictably and eat into the very frontier this bench
	# needs to plant the attacker on, so this fixture pins the headcount to
	# exactly 2 (the centred core + one random AI starter) instead.
	cfg.camp_sizes = [2]

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)

	var t_gen := Time.get_ticks_msec()
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var gen_ms := Time.get_ticks_msec() - t_gen
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_true(starting_nodes.size() >= 2,
		"need both a player core and an AI-starter core for a hostile target set")
	if starting_nodes.size() < 2:
		return

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child(_alloc)

	_attacker = _ENTITY_SCENE.instantiate() as Entity
	_attacker.name = "BenchAttacker"
	_attacker.display_name = "BenchAttacker"
	_attacker.core_class = _CORE_CLASS
	# Both Entity's default faction is npc.tres (same id => ALLY) — the
	# attacker needs a distinct faction or Ownership.HOSTILE filtering finds
	# nothing to target at all. player.tres vs. the defender's default npc.tres.
	_attacker.faction = _PLAYER_FACTION
	_graph.entities_container.add_child(_attacker)

	_defender = _ENTITY_SCENE.instantiate() as Entity
	_defender.name = "BenchDefender"
	_defender.display_name = "BenchDefender"
	_defender.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_defender)
	await get_tree().process_frame

	_alloc.force_allocate(_defender, starting_nodes[1])
	_defender.core_location = starting_nodes[1]

	_policy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	_policy.rng = rng
	_grow(_defender, _DEFENDER_CHECKPOINTS[0], _policy)

	var frontline := _find_frontline_node()
	assert_not_null(frontline,
		"defender territory must border at least one unclaimed node to plant the attacker on")
	if frontline == null:
		return
	_alloc.force_allocate(_attacker, frontline)
	_attacker.core_location = frontline

	_plan = MagicAttackPlan.new()
	_plan.attacker = _attacker
	_plan.spell = _TRAIL_BLAZER
	_plan._on_node_left_clicked(frontline)
	assert_eq(_plan.source, frontline, "the plan must have accepted the frontline node as source")

	gut.p("--- fixture: %s, node_count=%d, edges=%d, seed=0x%X, generated in %d ms ---"
		% [_PRESET.resource_path.get_file(), _graph.get_skill_nodes().size(),
			_graph.get_edges().size(), _SEED, gen_ms])
	gut.p("defender owned: %d, attacker foothold: frontline node bordering defender territory"
		% _defender.navigator.get_mirrored_nodes().size())


## First unclaimed node touching defender territory — the realistic "player
## standing at the border" cast position, planted rather than grown into
## because [AllocationPolicy]'s BFS-ball frontier has no reason to walk two
## independent blobs into contact within a bounded number of steps.
func _find_frontline_node() -> SkillNode:
	for owned_node in _defender.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null:
				return neighbour
	return null


func _frontier(entity: Entity) -> Array[SkillNode]:
	var frontier: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for owned_node in entity.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null and not seen.has(neighbour):
				seen[neighbour] = true
				frontier.append(neighbour)
	return frontier


func _grow(entity: Entity, target: int, policy: AllocationPolicy) -> void:
	var guard := 0
	while entity.navigator.get_mirrored_nodes().size() < target and guard < _MAX_FRONTIER_SEARCH:
		guard += 1
		var frontier := _frontier(entity)
		if frontier.is_empty():
			return
		var pick: SkillNode = policy.pick_next(entity, frontier, null)
		if pick == null:
			return
		_alloc.force_allocate(entity, pick)


func after_all() -> void:
	for n in [_attacker, _defender, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()


func _median(times: Array[int]) -> float:
	if times.is_empty():
		return 0.0
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


## Ramps DEFENDER owned count (see header) and, at each checkpoint, times
## [method MagicAttackPlan._rebuild_preview] across a sample of the real
## valid-target set for the planted (source, spell) pair — the shape of a
## player sweeping the mouse across several in-range enemies.
func test_rebuild_preview_cost_ramp() -> void:
	await _ensure_fixture()
	if _plan == null:
		return

	gut.p("")
	gut.p("defender | targets sampled | _edge_lookup (med) | _rebuild_preview (med) | worst | frames @144Hz (worst)")
	gut.p("  owned  |                 |                     |                        |       |")
	gut.p("---------+-----------------+---------------------+------------------------+-------+----------------------")

	var checkpoint_worst := 0.0

	for target in _DEFENDER_CHECKPOINTS:
		_grow(_defender, target, _policy)
		var owned := _defender.navigator.get_mirrored_nodes().size()

		var targets := _plan._valid_targets().keys()
		assert_false(targets.is_empty(),
			"the planted frontline source must see at least one hostile target in range")
		if targets.is_empty():
			continue
		var sample_size: int = mini(_TARGETS_SAMPLED_PER_CHECKPOINT, targets.size())

		var edge_lookup_times: Array[int] = []
		var rebuild_times: Array[int] = []
		var worst := 0.0

		for i in sample_size:
			var candidate: SkillNode = targets[i]
			_plan.set_hover_target(candidate)

			var lookup_samples: Array[int] = []
			for s in _SAMPLES_PER_TARGET:
				var t := Time.get_ticks_usec()
				var _lookup := _plan._edge_lookup(_graph)
				lookup_samples.append(Time.get_ticks_usec() - t)
			edge_lookup_times.append(int(_median(lookup_samples)))

			var rebuild_samples: Array[int] = []
			for s in _SAMPLES_PER_TARGET:
				_plan._preview_dirty = true
				var t2 := Time.get_ticks_usec()
				_plan._rebuild_preview()
				rebuild_samples.append(Time.get_ticks_usec() - t2)
			var rebuild_med := _median(rebuild_samples)
			rebuild_times.append(int(rebuild_med))
			worst = maxf(worst, rebuild_med)

		checkpoint_worst = maxf(checkpoint_worst, worst)
		gut.p("%8d | %15d | %19.0f us | %22.0f us | %5.0f | %6.2f"
			% [owned, sample_size, _median(edge_lookup_times), _median(rebuild_times), worst,
				worst / _FRAME_BUDGET_USEC])

	gut.p("")
	gut.p("worst _rebuild_preview across the whole ramp: %.0f us against a %.0f us 144Hz budget"
		% [checkpoint_worst, _FRAME_BUDGET_USEC])

	# Written red on #681 as the open defect, green since #695 (0.87x at 200
	# defender-owned — see the header). 2x budget, not 1x: it is the line the
	# whole-subgraph snapshot (2.79x measured) cannot get back under, with room
	# for a slower machine than the one that measured 0.87x.
	assert_lt(checkpoint_worst, 2.0 * _FRAME_BUDGET_USEC,
		("REGRESSION (#681/#695): worst _rebuild_preview cost %.0f us against a %.0f us "
			+ "144Hz frame budget, paid on EVERY preview-target change — is the shadow "
			+ "cloning every owned node board again? See this file's header.")
			% [checkpoint_worst, _FRAME_BUDGET_USEC])


## Where [method MagicAttackPlan._rebuild_preview]'s cost actually goes, at the
## ramp's final (largest) defender-owned checkpoint: mint the shadow world,
## resolve against it (the propagation walk PLUS the lazy [CombatWorld]
## snapshot it triggers — the two aren't separable from outside [CombatWorld]),
## then free it. Same three calls [method SpellResolver.resolve] makes
## internally, timed individually instead of as one opaque total.
func test_shadow_world_lifecycle_attribution() -> void:
	await _ensure_fixture()
	if _plan == null:
		return
	var targets := _plan._valid_targets().keys()
	if targets.is_empty():
		return
	var candidate: SkillNode = targets[0]

	var mint_times: Array[int] = []
	var resolve_times: Array[int] = []
	var teardown_times: Array[int] = []
	for s in _SAMPLES_PER_TARGET:
		var t := Time.get_ticks_usec()
		var world := CombatWorld.shadow()
		mint_times.append(Time.get_ticks_usec() - t)

		var t2 := Time.get_ticks_usec()
		var _outcome := SpellResolver.resolve_against(
			_TRAIL_BLAZER, candidate, _plan.source, _attacker, _graph, world)
		resolve_times.append(Time.get_ticks_usec() - t2)

		var t3 := Time.get_ticks_usec()
		world.free_shadow()
		teardown_times.append(Time.get_ticks_usec() - t3)

	var mint := _median(mint_times)
	var resolve := _median(resolve_times)
	var teardown := _median(teardown_times)
	var total := mint + resolve + teardown
	gut.p("")
	gut.p("shadow world lifecycle at %d defender owned, one candidate, median of %d:"
		% [_defender.navigator.get_mirrored_nodes().size(), _SAMPLES_PER_TARGET])
	gut.p("  CombatWorld.shadow() mint      %7.0f us (%4.1f%%)" % [mint, 100.0 * mint / total])
	gut.p("  SpellResolver.resolve_against  %7.0f us (%4.1f%%)  <- walk + per-node lazy snapshot (#695)"
		% [resolve, 100.0 * resolve / total])
	gut.p("  world.free_shadow()            %7.0f us (%4.1f%%)" % [teardown, 100.0 * teardown / total])
	gut.p("  total                          %7.0f us" % total)
	assert_gt(total, 0.0, "the lifecycle must be measurable at all")
