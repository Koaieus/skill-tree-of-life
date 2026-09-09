extends GutTest

## Acceptance for #477 — removable-blocker placement (#300). Verifies
## [GraphProcgen.generate] returns a `blockers` array of `{node, size, prune_seed,
## footprint}`
## placements, that the per-tier density is `floor(node_count / denom)`, that
## placements never land on a starter core or a keystone node, that no node is
## picked twice, and that placements are seed-deterministic.

const _KEYSTONE := preload("res://entity/keystone/instances/xp_anchor_keystone.tres")


func _build_config(node_count: int, rng_seed: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.topology = GraphProcgenTopology.new()
	cfg.topology.node_count = node_count
	cfg.seed = rng_seed
	cfg.shape = GraphProcgenShape.new()
	cfg.shape.shape_mask = CircularShapeMask.new()
	cfg.starting = GraphProcgenStartingPoints.new()
	cfg.content = GraphProcgenContent.new()
	cfg.blockers = GraphProcgenBlockers.new()
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Dictionary:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	return await GraphProcgen.generate(cfg, graph)


func _counts(blockers: Array) -> Dictionary:
	var out := {}
	for placement in blockers:
		var size: int = placement.get("size")
		out[size] = out.get(size, 0) + 1
	return out


func _positions(blockers: Array) -> Array:
	var out := []
	for placement in blockers:
		out.append((placement.get("node") as SkillNode).position)
	return out


func test_density_at_50_nodes() -> void:
	var cfg := _build_config(50, 12345)
	cfg.blockers.blocker_per_small = 10
	cfg.blockers.blocker_per_medium = 25
	cfg.blockers.blocker_per_large = 100
	var result: Dictionary = await _generate(cfg)
	var blockers: Array = result.get("blockers", [])
	var counts := _counts(blockers)
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 5, "50/10 = 5 small")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 2, "50/25 = 2 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 0, "50/100 = 0 large")
	assert_eq(blockers.size(), 7, "total placements = 5 + 2 + 0")


func test_density_at_100_nodes() -> void:
	var cfg := _build_config(100, 4242)
	cfg.blockers.blocker_per_small = 10
	cfg.blockers.blocker_per_medium = 25
	cfg.blockers.blocker_per_large = 100
	var result: Dictionary = await _generate(cfg)
	var counts := _counts(result.get("blockers", []))
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 10, "100/10 = 10 small")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 4, "100/25 = 4 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 1, "100/100 = 1 large")


func test_placements_skip_starters_and_keystones() -> void:
	var cfg := _build_config(60, 777)
	# Not what this test is about, and 60 nodes is small enough that the #300
	# safe radius swallows the whole eligible pool — the radius has its own
	# test below.
	cfg.blockers.blocker_min_hops_from_core = 0
	var sp := StartingPoint.new()
	sp.position = Vector2.ZERO
	cfg.starting.starting_points.append(sp)
	var kp := KeystonePlacement.new()
	kp.keystone = _KEYSTONE
	cfg.content.guaranteed_placements.append(kp)

	var result: Dictionary = await _generate(cfg)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 1, "one manual starter anchor")
	var blockers: Array = result.get("blockers", [])
	assert_gt(blockers.size(), 0, "expected some blocker placements")

	var starter_ids := {}
	for sn in starting_nodes:
		starter_ids[sn.get_instance_id()] = true
	var seen := {}
	for placement in blockers:
		var node: SkillNode = placement.get("node")
		assert_false(starter_ids.has(node.get_instance_id()), "blocker must not be a starter core")
		assert_null(node.keystone, "blocker must not be a keystone node")
		assert_false(seen.has(node.get_instance_id()), "no node picked twice")
		seen[node.get_instance_id()] = true


func test_same_seed_same_placements() -> void:
	var cfg_a := _build_config(80, 9999)
	cfg_a.blockers.blocker_per_small = 10
	cfg_a.blockers.blocker_per_medium = 25
	cfg_a.blockers.blocker_per_large = 100
	var cfg_b := _build_config(80, 9999)
	cfg_b.blockers.blocker_per_small = 10
	cfg_b.blockers.blocker_per_medium = 25
	cfg_b.blockers.blocker_per_large = 100

	var result_a: Dictionary = await _generate(cfg_a)
	var result_b: Dictionary = await _generate(cfg_b)
	assert_eq(
		_positions(result_a.get("blockers", [])), _positions(result_b.get("blockers", [])),
		"same seed must yield identical placements")


func test_denom_zero_disables_tier() -> void:
	var cfg := _build_config(50, 42)
	cfg.blockers.blocker_per_small = 0
	cfg.blockers.blocker_per_medium = 0
	cfg.blockers.blocker_per_large = 0
	var result: Dictionary = await _generate(cfg)
	assert_eq((result.get("blockers", []) as Array).size(), 0, "all denoms 0 → no blockers")

	cfg = _build_config(50, 43)
	cfg.blockers.blocker_per_small = 0
	cfg.blockers.blocker_per_medium = 5
	cfg.blockers.blocker_per_large = 0
	result = await _generate(cfg)
	var counts := _counts(result.get("blockers", []))
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 0, "small disabled")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 10, "50/5 = 10 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 0, "large disabled")


func test_denom_below_floor_clamps_to_min() -> void:
	# A joker authoring denom 1 (or 2..4) must not get "one blocker per node":
	# the placement pass clamps any positive denominator up to MIN_BLOCKER_PER.
	var cfg := _build_config(50, 555)
	cfg.blockers.blocker_per_small = 1
	cfg.blockers.blocker_per_medium = 2
	cfg.blockers.blocker_per_large = 3
	var result: Dictionary = await _generate(cfg)
	var counts := _counts(result.get("blockers", []))
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 10, "denom 1 clamps to 5 → 50/5 = 10")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 10, "denom 2 clamps to 5 → 10")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 10, "denom 3 clamps to 5 → 10")


func _hops_from(graph: Graph, nodes: Array, origins: Array, max_hops: int) -> Dictionary:
	# BFS over the live graph, returning {instance_id: true} for every node
	# within `max_hops` of any origin SkillNode.
	var seen := {}
	var frontier: Array[SkillNode] = []
	for o in origins:
		seen[(o as SkillNode).get_instance_id()] = true
		frontier.append(o)
	var hops := 0
	while hops < max_hops and not frontier.is_empty():
		var next: Array[SkillNode] = []
		for n in frontier:
			for nb in graph.get_neighbours(n):
				if seen.has(nb.get_instance_id()):
					continue
				seen[nb.get_instance_id()] = true
				next.append(nb)
		frontier = next
		hops += 1
	return seen


func test_no_blocker_inside_core_safe_radius() -> void:
	# #300 — no blocker within `blocker_min_hops_from_core` hops of ANY camp
	# core, the human's and every AI camp's alike.
	var cfg := _build_config(300, 31337)
	cfg.starting.starter_placement = CenterCoreStarters.new()
	cfg.camp_sizes = [3]
	cfg.blockers.blocker_min_hops_from_core = 6
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)

	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 3, "three camp cores")
	var blockers: Array = result.get("blockers", [])
	assert_gt(blockers.size(), 0, "expected some blocker placements outside the safe radius")

	var forbidden := _hops_from(graph, result.get("nodes", []), starting_nodes, 6)
	for placement in blockers:
		var node: SkillNode = placement.get("node")
		assert_false(
			forbidden.has(node.get_instance_id()),
			"blocker at %s is within 6 hops of a core" % str(node.position))


func test_safe_radius_zero_allows_core_adjacent_blockers() -> void:
	# The knob is opt-out: 0 restores the pre-#300 "anywhere but a core or a
	# keystone" pool, so the ring one hop off a core is eligible again.
	var cfg := _build_config(300, 31337)
	cfg.starting.starter_placement = CenterCoreStarters.new()
	cfg.camp_sizes = [3]
	cfg.blockers.blocker_min_hops_from_core = 0
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)

	var starting_nodes: Array = result.get("starting_nodes", [])
	var near := _hops_from(graph, result.get("nodes", []), starting_nodes, 6)
	var any_near := false
	for placement in result.get("blockers", []):
		if near.has((placement.get("node") as SkillNode).get_instance_id()):
			any_near = true
			break
	assert_true(any_near, "with the radius disabled some blocker lands near a core")


# ── #586: the per-placement loot-book prune seed ─────────────────────────────

func test_placements_carry_a_reproducible_prune_seed() -> void:
	# Rides the same derived stream as placement, so a given procgen seed
	# reproduces both WHERE blockers are and WHAT each one offers — every
	# peer re-runs the level scene rather than being told the result.
	var cfg_a := _build_config(100, 4242)
	cfg_a.blockers.blocker_per_small = 10
	cfg_a.blockers.blocker_per_medium = 25
	cfg_a.blockers.blocker_per_large = 100
	var cfg_b := _build_config(100, 4242)
	cfg_b.blockers.blocker_per_small = 10
	cfg_b.blockers.blocker_per_medium = 25
	cfg_b.blockers.blocker_per_large = 100
	var seeds_a := _prune_seeds((await _generate(cfg_a)).get("blockers", []))
	var seeds_b := _prune_seeds((await _generate(cfg_b)).get("blockers", []))
	assert_gt(seeds_a.size(), 1, "expected several blocker placements")
	assert_eq(seeds_a, seeds_b, "same procgen seed → same prune seeds")

	var distinct := {}
	for s in seeds_a:
		distinct[s] = true
	assert_gt(distinct.size(), 1, "blockers do not all share one seed")


func test_prune_seed_stream_does_not_shift_placements() -> void:
	# The seeds are drawn from the dedicated blocker stream AFTER placement,
	# so adding them must not move a single blocker — this is the guard on
	# that ordering (the same reason the stream is derived, not shared).
	var cfg := _build_config(100, 4242)
	cfg.blockers.blocker_per_small = 10
	cfg.blockers.blocker_per_medium = 25
	cfg.blockers.blocker_per_large = 100
	var result: Dictionary = await _generate(cfg)
	var counts := _counts(result.get("blockers", []))
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 10, "100/10 = 10 small")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 4, "100/25 = 4 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 1, "100/100 = 1 large")


func _prune_seeds(blockers: Array) -> Array[int]:
	var out: Array[int] = []
	for placement in blockers:
		assert_true(placement.has("prune_seed"), "every placement carries a prune seed")
		out.append(int(placement.get("prune_seed")))
	return out


# ── #777: the bonus-node footprint ───────────────────────────────────────────

func _footprint_of(placement: Dictionary) -> Array:
	assert_true(placement.has("footprint"), "every placement carries a footprint")
	return placement.get("footprint") as Array


## Every placement's footprint sits inside its tier's authored range — the
## count is the ONLY thing #777 pins, because the ranges themselves are the
## owner's to tune (`owner_tunes_agents`).
func test_footprint_count_is_within_the_authored_range_per_tier() -> void:
	var cfg := _build_config(300, 8112)
	cfg.blockers.blocker_min_hops_from_core = 0
	cfg.blockers.blocker_per_small = 20
	cfg.blockers.blocker_per_medium = 40
	cfg.blockers.blocker_per_large = 80
	var result: Dictionary = await _generate(cfg)
	var blockers: Array = result.get("blockers", [])
	assert_gt(blockers.size(), 0, "expected some blocker placements")
	var saw_medium := false
	for placement in blockers:
		var size: int = placement.get("size")
		var span := cfg.blockers.footprint_range(size)
		var n := _footprint_of(placement).size()
		assert_between(n, span.x, span.y,
				"a %s blocker's footprint must sit in [%d, %d]"
				% [GameRoot.BlockerSize.keys()[size], span.x, span.y])
		if size == GameRoot.BlockerSize.MEDIUM:
			saw_medium = true
	assert_true(saw_medium, "the sample includes a tier whose range floor is > 0")


## The whole point of growing through a frontier rather than sampling a hop
## ball: a footprint is CONNECTED to its core, so the falloff aura's
## hop-from-core is defined for every node it owns.
func test_footprint_is_connected_to_its_core() -> void:
	var cfg := _build_config(300, 616)
	cfg.blockers.blocker_min_hops_from_core = 0
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	for placement in result.get("blockers", []):
		var owned := {(placement.get("node") as SkillNode).get_instance_id(): true}
		var pending: Array = _footprint_of(placement).duplicate()
		# Repeatedly absorb any pending node adjacent to what is already owned.
		# A footprint that never drains is disconnected from its core.
		var progressed := true
		while progressed and not pending.is_empty():
			progressed = false
			for i in range(pending.size() - 1, -1, -1):
				var node: SkillNode = pending[i]
				for nb in graph.get_neighbours(node):
					if owned.has(nb.get_instance_id()):
						owned[node.get_instance_id()] = true
						pending.remove_at(i)
						progressed = true
						break
		assert_eq(pending.size(), 0,
				"footprint of the blocker at %s is disconnected from its core"
				% str((placement.get("node") as SkillNode).position))


## No node belongs to two Dormant Cores, and no footprint node is a core, a
## starter or a keystone — the claim set covers cores placed LATER in the tier
## order, not just the ones already grown.
func test_footprints_never_overlap_a_claim_a_starter_or_a_keystone() -> void:
	var cfg := _build_config(300, 2024)
	cfg.blockers.blocker_min_hops_from_core = 0
	var sp := StartingPoint.new()
	sp.position = Vector2.ZERO
	cfg.starting.starting_points.append(sp)
	var kp := KeystonePlacement.new()
	kp.keystone = _KEYSTONE
	cfg.content.guaranteed_placements.append(kp)
	var result: Dictionary = await _generate(cfg)

	var starter_ids := {}
	for sn in result.get("starting_nodes", []):
		starter_ids[(sn as SkillNode).get_instance_id()] = true
	var claimed := {}
	for placement in result.get("blockers", []):
		var core: SkillNode = placement.get("node")
		assert_false(claimed.has(core.get_instance_id()), "a core is claimed once")
		claimed[core.get_instance_id()] = true
	var total_footprint := 0
	for placement in result.get("blockers", []):
		for node: SkillNode in _footprint_of(placement):
			total_footprint += 1
			assert_false(claimed.has(node.get_instance_id()),
					"node at %s is claimed twice" % str(node.position))
			assert_false(starter_ids.has(node.get_instance_id()),
					"a footprint node must not be a starter core")
			assert_null(node.keystone, "a footprint node must not be a keystone")
			claimed[node.get_instance_id()] = true
	assert_gt(total_footprint, 0, "expected the sample to grow some footprints")


## #777 decision 6 — the safe radius guards the whole TERRITORY, not just the
## node the Dormant Core sits on. A 3-node footprint reaching into a camp's
## opening ball is exactly the "boxed in by boulders" failure #300 named.
func test_no_footprint_node_inside_the_core_safe_radius() -> void:
	var cfg := _build_config(300, 31337)
	cfg.starting.starter_placement = CenterCoreStarters.new()
	cfg.camp_sizes = [3]
	cfg.blockers.blocker_min_hops_from_core = 6
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)

	var starting_nodes: Array = result.get("starting_nodes", [])
	var forbidden := _hops_from(graph, result.get("nodes", []), starting_nodes, 6)
	var seen_any := false
	for placement in result.get("blockers", []):
		for node: SkillNode in _footprint_of(placement):
			seen_any = true
			assert_false(forbidden.has(node.get_instance_id()),
					"footprint node at %s is within 6 hops of a core" % str(node.position))
	assert_true(seen_any, "expected footprints to exist outside the safe radius")


func _footprint_positions(blockers: Array) -> Array:
	var out := []
	for placement in blockers:
		var per := []
		for node: SkillNode in (placement.get("footprint") as Array):
			per.append(node.position)
		out.append(per)
	return out


func test_same_seed_same_footprints() -> void:
	var result_a: Dictionary = await _generate(_build_config(200, 5150))
	var result_b: Dictionary = await _generate(_build_config(200, 5150))
	var fa := _footprint_positions(result_a.get("blockers", []))
	assert_gt(fa.size(), 0, "expected some blocker placements")
	assert_eq(fa, _footprint_positions(result_b.get("blockers", [])),
			"same seed must yield identical footprints")


## The footprint draws are APPENDED to the blocker stream, after the cores and
## the prune seeds — so turning footprints on cannot move a blocker or change
## what it offers. Same guard, and same reason, as
## `test_prune_seed_stream_does_not_shift_placements`.
func test_footprint_stream_does_not_shift_placements_or_prune_seeds() -> void:
	var cfg_off := _build_config(200, 5150)
	cfg_off.blockers.footprint_small_min = 0
	cfg_off.blockers.footprint_small_max = 0
	cfg_off.blockers.footprint_medium_min = 0
	cfg_off.blockers.footprint_medium_max = 0
	cfg_off.blockers.footprint_large_min = 0
	cfg_off.blockers.footprint_large_max = 0
	var off: Dictionary = await _generate(cfg_off)
	var on: Dictionary = await _generate(_build_config(200, 5150))

	assert_eq(_positions(on.get("blockers", [])), _positions(off.get("blockers", [])),
			"footprints must not move a single blocker")
	assert_eq(_prune_seeds(on.get("blockers", [])), _prune_seeds(off.get("blockers", [])),
			"footprints must not change a single prune seed")
	var grown := 0
	for placement in on.get("blockers", []):
		grown += (placement.get("footprint") as Array).size()
	assert_gt(grown, 0, "the on-config actually grew something")


## Shrink-to-fit, not steal-a-claim: a range asking for more neighbours than the
## map can spare hands back what fits and drops nobody. Every tier at denom 5 on
## a small board saturates the eligible pool by construction.
func test_footprint_shrinks_to_fit_a_saturated_board() -> void:
	var cfg := _build_config(60, 4711)
	cfg.blockers.blocker_min_hops_from_core = 0
	cfg.blockers.blocker_per_small = 5
	cfg.blockers.blocker_per_medium = 5
	cfg.blockers.blocker_per_large = 5
	cfg.blockers.footprint_small_min = 6
	cfg.blockers.footprint_small_max = 6
	cfg.blockers.footprint_medium_min = 6
	cfg.blockers.footprint_medium_max = 6
	cfg.blockers.footprint_large_min = 6
	cfg.blockers.footprint_large_max = 6
	var result: Dictionary = await _generate(cfg)
	var blockers: Array = result.get("blockers", [])
	assert_eq(blockers.size(), 36, "the blocker COUNT is never what shrinks (3 × 60/5)")
	var claimed := {}
	var short := 0
	for placement in blockers:
		claimed[(placement.get("node") as SkillNode).get_instance_id()] = true
		var n := _footprint_of(placement).size()
		assert_lte(n, 6, "never more than the roll")
		if n < 6:
			short += 1
		for node: SkillNode in _footprint_of(placement):
			assert_false(claimed.has(node.get_instance_id()), "still no double claim")
			claimed[node.get_instance_id()] = true
	assert_gt(short, 0, "a saturated board must actually shrink some footprint")
