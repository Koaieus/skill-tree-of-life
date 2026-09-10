extends GutTest

## Coverage for #378 slice C — [AiBladeRollout]'s bounded melee candidate
## search: the free reach-bound rejection, the greedy directional chain, and
## the full pivot->proposal->coarse-rank->full-resolve pipeline end to end
## (real physics — MeleeAttackPlan.resolve() drives an actual BladeHitScan).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _ai_entity: Entity
var _hostile: Entity


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if faction != null:
		e.faction = faction
	return e


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	_graph.add_edge(a, b)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_ai_entity = _make_entity("AI")
	_graph.add_child(_ai_entity)

	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.add_child(_hostile)

	await get_tree().process_frame


# ── _reach_bound: free-rejection math, no simulation ────────────────────────

func test_reach_bound_zero_hops_is_zero() -> void:
	var pivot := _spawn("Pivot")
	pivot.global_position = Vector2.ZERO
	var adjacency := {pivot: []}
	assert_almost_eq(AiBladeRollout._reach_bound(pivot, adjacency, 0), 0.0, 0.001)


func test_reach_bound_sums_edge_length_along_path() -> void:
	var pivot := _spawn("Pivot")
	var a := _spawn("A")
	var b := _spawn("B")
	pivot.global_position = Vector2.ZERO
	a.global_position = Vector2(50.0, 0.0)
	b.global_position = Vector2(50.0, 50.0)
	var adjacency := {pivot: [a], a: [pivot, b], b: [a]}
	assert_almost_eq(AiBladeRollout._reach_bound(pivot, adjacency, 1), 50.0, 0.01,
			"1 hop reaches only A, 50 px away")
	assert_almost_eq(AiBladeRollout._reach_bound(pivot, adjacency, 2), 100.0, 0.01,
			"2 hops reaches B via A, 50 + 50 px along the path")


## A node reachable by a SHORT path (visited first, breadth-first) and also
## by a LONGER path must report the longer cumulative distance — an
## admissible reach bound has to be the max over every path, not whichever
## one the search happened to see first. Regression for a bug where a
## first-arrival-only visited set silently under-counted branchy territory.
func test_reach_bound_prefers_the_longer_of_two_paths_to_the_same_node() -> void:
	var pivot := _spawn("Pivot")
	var short_mid := _spawn("ShortMid")
	var long_mid := _spawn("LongMid")
	var c := _spawn("C")
	pivot.global_position = Vector2.ZERO
	short_mid.global_position = Vector2(10.0, 0.0)
	long_mid.global_position = Vector2(10.0, 100.0)
	c.global_position = Vector2(10.0, 5.0)
	var adjacency := {
		pivot: [short_mid, long_mid],
		short_mid: [pivot, c],
		long_mid: [pivot, c],
		c: [short_mid, long_mid],
	}
	# Short route: pivot->short_mid (10) -> c (5) = 15.
	# Long route: pivot->long_mid (~100.5) -> c (~95) = ~195.5.
	# Breadth-first order visits short_mid before long_mid, so a first-
	# arrival-only bound would freeze c's distance at 15.
	assert_gt(AiBladeRollout._reach_bound(pivot, adjacency, 2), 190.0,
			"the bound must reflect the longer path to C, not the first one found")


# ── _prune_pivots: distance-only rejection (full-circle sweep) ─────────────

func test_prune_pivots_rejects_out_of_reach_and_keeps_in_reach() -> void:
	var near_pivot := _spawn("Near")
	var far_pivot := _spawn("Far")
	near_pivot.global_position = Vector2(100.0, 0.0)
	far_pivot.global_position = Vector2(-10000.0, 0.0)
	# blade_size default (fixture entity, STR=10, no core bonus) is 1 —
	# reach bound at 1 hop with no owned neighbours is 0, so make each its
	# own pivot with itself as the only reachable point (0-length "self hop").
	var adjacency := {near_pivot: [], far_pivot: []}
	var enemy_positions: Array[Vector2] = [Vector2(100.0, 0.0)]
	# max_size is read off blade_size directly inside _prune_pivots, and the
	# fixture board's default blade_size is 1 — reach bound over an empty
	# neighbour list is 0, so neither pivot can register a nonzero bound.
	# What DOES differ is nearest-enemy distance, which the bound is compared
	# against: near_pivot sits ON the enemy (bound 0 >= nearest 0 -> keep),
	# far_pivot is 10000 px away (bound 0 < nearest -> reject).
	var out := AiBladeRollout._prune_pivots(adjacency, enemy_positions)
	var kept: Array[SkillNode] = []
	for c in out:
		kept.append(c[0])
	assert_true(kept.has(near_pivot), "a pivot standing on the enemy always survives")
	assert_false(kept.has(far_pivot), "a pivot 10000px away with 0 reach cannot survive")


# ── _grow_path: a genuine consecutive-from-pivot walk (#823) ───────────

func test_grow_path_picks_nearer_neighbour_first() -> void:
	var pivot := _spawn("Pivot")
	var near := _spawn("Near")
	var far := _spawn("Far")
	pivot.global_position = Vector2.ZERO
	near.global_position = Vector2(50.0, 0.0)
	far.global_position = Vector2(0.0, 500.0)
	var adjacency := {pivot: [near, far], near: [pivot], far: [pivot]}
	var path := AiBladeRollout._grow_path(pivot, adjacency, Vector2(60.0, 0.0), 2)
	assert_eq(path.size(), 1,
		"far is not a neighbour of near, so a genuine path stops at 1 " +
		"(unlike the retired tree-growing _greedy_chain, which would " +
		"have picked both off the pivot directly)")
	assert_eq(path[0], near, "the neighbour closer to the target is picked first")


func test_grow_path_walks_consecutively_from_the_tip() -> void:
	var pivot := _spawn("Pivot")
	var n1 := _spawn("N1")
	var n2 := _spawn("N2")
	pivot.global_position = Vector2.ZERO
	n1.global_position = Vector2(50.0, 0.0)
	n2.global_position = Vector2(100.0, 0.0)
	var adjacency := {pivot: [n1], n1: [pivot, n2], n2: [n1]}
	var path := AiBladeRollout._grow_path(pivot, adjacency, Vector2(200.0, 0.0), 5)
	assert_eq(path, [n1, n2], "a real chain walks outward from the tip, not just the pivot")


func test_grow_path_stops_when_no_neighbours_left() -> void:
	var pivot := _spawn("Pivot")
	pivot.global_position = Vector2.ZERO
	var adjacency := {pivot: []}
	var path := AiBladeRollout._grow_path(pivot, adjacency, Vector2(100.0, 0.0), 5)
	assert_eq(path.size(), 0, "no owned neighbours -> empty path, not an infinite loop")


# ── _build_archetype: rigidify-then-reach (#823) ────────────────────────────

func test_archetype_no_clamp_when_pivot_adjacent_joint_already_triangulated() -> void:
	var pivot := _spawn("Pivot")
	var c := _spawn("C")
	var n1 := _spawn("N1")
	pivot.global_position = Vector2.ZERO
	c.global_position = Vector2(50.0, 0.0)
	n1.global_position = Vector2(50.0, 50.0)
	_add_edge(pivot, c)
	_add_edge(c, n1)
	_add_edge(pivot, n1) # closes the triangle Pivot-C-N1
	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, c)
	_alloc.force_allocate(_ai_entity, n1)
	await get_tree().process_frame

	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var archetype := AiBladeRollout._build_archetype(pivot, adjacency, c.global_position, 2, 2)
	var clamps: Array[SkillNode] = archetype.clamps
	assert_true(clamps.is_empty(),
			"the pivot-adjacent joint is already part of a triangle — clamping it would only " +
			"add a redundant constraint")


func test_archetype_procgen_clamp_is_free_rigidity() -> void:
	var pivot := _spawn("Pivot")
	var c := _spawn("C")
	var n1 := _spawn("N1")
	pivot.global_position = Vector2.ZERO
	c.global_position = Vector2(50.0, 0.0)
	n1.global_position = Vector2(100.0, 0.0)
	_add_edge(pivot, c)
	_add_edge(c, n1)
	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, c)
	_alloc.force_allocate(_ai_entity, n1)
	var clamp_scene := preload("res://skill_node/addons/clamp_addon.tscn")
	var real_clamp := clamp_scene.instantiate() as ClampAddon
	c.add_child(real_clamp)
	await get_tree().process_frame

	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var archetype := AiBladeRollout._build_archetype(pivot, adjacency, n1.global_position, 3, 2)
	var members: Array[SkillNode] = archetype.members
	var clamps: Array[SkillNode] = archetype.clamps
	assert_true(members.has(c) and members.has(n1), "both handle nodes are still selected")
	assert_false(clamps.has(c), "C already carries a procgen ClampAddon — free, never spent")
	assert_true(members.size() + clamps.size() <= 3, "budget respected: C cost only 1, not 2")


func test_archetype_never_proposes_a_clamp_on_a_full_slot_node() -> void:
	var pivot := _spawn("Pivot")
	var c := _spawn("C")
	var n1 := _spawn("N1")
	pivot.global_position = Vector2.ZERO
	c.global_position = Vector2(50.0, 0.0)
	n1.global_position = Vector2(100.0, 0.0)
	_add_edge(pivot, c)
	_add_edge(c, n1)
	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, c)
	_alloc.force_allocate(_ai_entity, n1)
	# force_allocate gives allocation_level 1 -> addon_slots == 1; filling it
	# with a DIFFERENT addon (not Clamp) leaves no slot AND no `has_addon`
	# free-rigidity match, so this specifically exercises the slot gate.
	var spike_scene := preload("res://skill_node/addons/spike_ring_addon.tscn")
	var spike := spike_scene.instantiate() as SpikeRingAddon
	c.add_child(spike)
	await get_tree().process_frame

	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var archetype := AiBladeRollout._build_archetype(pivot, adjacency, n1.global_position, 2, 1)
	var clamps: Array[SkillNode] = archetype.clamps
	assert_false(clamps.has(c), "C's single addon_slot is already spent on the spike ring")


func test_archetype_consecutive_gap_does_not_extend_the_handle() -> void:
	var pivot := _spawn("Pivot")
	var n1 := _spawn("N1")
	var n2 := _spawn("N2")
	pivot.global_position = Vector2.ZERO
	n1.global_position = Vector2(50.0, 0.0)
	n2.global_position = Vector2(100.0, 0.0)
	_add_edge(pivot, n1)
	_add_edge(n1, n2)
	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, n1)
	_alloc.force_allocate(_ai_entity, n2)
	var spike_scene := preload("res://skill_node/addons/spike_ring_addon.tscn")
	var spike := spike_scene.instantiate() as SpikeRingAddon
	n1.add_child(spike) # N1's one slot is spent -> can't be clamped
	await get_tree().process_frame

	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var archetype := AiBladeRollout._build_archetype(pivot, adjacency, n2.global_position, 3, 2)
	var members: Array[SkillNode] = archetype.members
	var clamps: Array[SkillNode] = archetype.clamps
	assert_true(members.has(n2), "N2 is still reached as a plain reach member")
	assert_true(clamps.is_empty(),
			"N1 (consecutive-from-pivot) can't be clamped, so N2's clamp would buy nothing " +
			"(#771 D2) and must not be proposed even though N2 itself could take one")


# ── D4 tier ladder + #823 requirement 3's "accidental, never sought" ───────

## A long, unclamped, untriangulated straight line so the handle never runs
## into a triangulation freebie or a slot/budget gap — clamps.size() tracks
## handle_target exactly, which is what lets this pin the RNG draw itself.
func _build_long_straight_chain(count: int) -> Array[SkillNode]:
	var pivot := _spawn("Pivot")
	pivot.global_position = Vector2.ZERO
	var chain: Array[SkillNode] = [pivot]
	for i in count:
		var n := _spawn("N%d" % i)
		n.global_position = Vector2(50.0 * (i + 1), 0.0)
		_add_edge(chain[-1], n)
		chain.append(n)
	for n in chain:
		_alloc.force_allocate(_ai_entity, n)
	_ai_entity.core_location = pivot
	return chain


func test_tier_ladder_bounds_the_handle_target() -> void:
	var chain := _build_long_straight_chain(6)
	await get_tree().process_frame
	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var target: Vector2 = chain[-1].global_position

	var rng0 := RandomNumberGenerator.new()
	rng0.seed = 42
	var proposals0 := AiBladeRollout._propose_blade_selections(
			[[chain[0], 10]], adjacency, target, 0, rng0)
	assert_gt(proposals0.size(), 0)
	var clamps0: Array[SkillNode] = proposals0[0][3]
	assert_true(clamps0.size() == 0 or clamps0.size() == 1,
			"ai_tier=0 rolls a handle target of 0 or 1, got %d" % clamps0.size())

	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 42
	var proposals3 := AiBladeRollout._propose_blade_selections(
			[[chain[0], 10]], adjacency, target, 3, rng3)
	assert_gt(proposals3.size(), 0)
	var clamps3: Array[SkillNode] = proposals3[0][3]
	assert_true(clamps3.size() == 3 or clamps3.size() == 4,
			"ai_tier=3 rolls a handle target of 3 or 4, got %d" % clamps3.size())


func test_tier_zero_can_land_accidentally_rigid_without_steering() -> void:
	var pivot := _spawn("Pivot")
	var a := _spawn("A")
	var b := _spawn("B")
	pivot.global_position = Vector2.ZERO
	a.global_position = Vector2(50.0, 0.0)
	b.global_position = Vector2(50.0, 50.0)
	_add_edge(pivot, a)
	_add_edge(a, b)
	_add_edge(pivot, b) # Pivot-A-B is a natural triangle in the topology
	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, a)
	_alloc.force_allocate(_ai_entity, b)
	await get_tree().process_frame

	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var proposals := AiBladeRollout._propose_blade_selections(
			[[pivot, 2]], adjacency, a.global_position, 0, rng)
	assert_gt(proposals.size(), 0)
	var members: Array[SkillNode] = proposals[0][1]
	var clamps: Array[SkillNode] = proposals[0][3]
	assert_true(clamps.is_empty(),
			"tier 0 never deliberately spends a clamp here, regardless of what it rolls")
	assert_eq(members.size(), 2, "both triangle members are still reached")

	# The resulting BLADE is genuinely rigid — the triangle's own induced
	# edges, not a clamp, make it so ("accidental truss, all good").
	var plan := MeleeAttackPlan.new()
	plan.attacker = _ai_entity
	plan.source = pivot
	plan.blade_nodes = members
	var state := plan.build_blade_state()
	assert_true(state.is_triangulated(1), "the induced Pivot-A-B triangle rigidifies A for free")


# ── Requirement 1: a handful per pivot, bounded as blade_size grows ────────

func test_proposal_count_per_pivot_stays_bounded_as_blade_size_grows() -> void:
	var chain := _build_long_straight_chain(70)
	await get_tree().process_frame
	var adjacency := AiBladeRollout._owned_adjacency(_ai_entity)
	var target: Vector2 = chain[-1].global_position
	for max_size in [2, 16, 64]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var proposals := AiBladeRollout._propose_blade_selections(
				[[chain[0], max_size]], adjacency, target, 1, rng)
		assert_true(proposals.size() <= 4,
				"blade_size=%d: expected at most 4 proposals for one pivot, got %d" \
						% [max_size, proposals.size()])


# ── Requirements 4/5: phantom clamps score exactly what a real one would ───

func test_phantom_clamp_matches_a_real_one_at_build_blade_state() -> void:
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_add_edge(source, joint)
	_add_edge(joint, tip)
	await get_tree().process_frame
	_alloc.force_allocate(_ai_entity, source)
	_alloc.force_allocate(_ai_entity, joint)
	_alloc.force_allocate(_ai_entity, tip)

	var real_plan := MeleeAttackPlan.new()
	real_plan.attacker = _ai_entity
	real_plan.source = source
	var members: Array[SkillNode] = [joint, tip]
	real_plan.blade_nodes = members
	var clamp_scene := preload("res://skill_node/addons/clamp_addon.tscn")
	var real_clamp := clamp_scene.instantiate() as ClampAddon
	joint.add_child(real_clamp)
	await get_tree().process_frame
	var real_state := real_plan.build_blade_state()

	joint.remove_child(real_clamp)
	real_clamp.free()
	var phantom_plan := MeleeAttackPlan.new()
	phantom_plan.attacker = _ai_entity
	phantom_plan.source = source
	phantom_plan.blade_nodes = members
	phantom_plan.ai_phantom_clamp_nodes = [joint]
	var phantom_state := phantom_plan.build_blade_state()

	assert_eq(phantom_state.constraints.size(), real_state.constraints.size(),
			"a phantom clamp must append exactly the same brace count as a real one")
	var real_pairs: Dictionary = {}
	for c in real_state.constraints:
		if c is BladeDistanceConstraint:
			real_pairs[Vector2i((c as BladeDistanceConstraint).a, (c as BladeDistanceConstraint).b)] = true
	for c in phantom_state.constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			assert_true(real_pairs.has(Vector2i(dc.a, dc.b)) or real_pairs.has(Vector2i(dc.b, dc.a)),
					"phantom constraint (%d,%d) has no real-clamp counterpart" % [dc.a, dc.b])


## Same claim, one level up — the FINALIST resolve (`plan.resolve()`, which
## builds its own BladeState internally) must see the phantom clamp too, not
## only a direct `build_blade_state()` call (#823 requirement 4's explicit
## warning: a parameter alone would reach the coarse tier and not this one).
## If `ai_phantom_clamp_nodes` only reached `build_blade_state()` when called
## directly, a phantom-clamped `resolve()` would silently swing unclamped —
## same geometry, fewer constraints, a DIFFERENT trajectory — and this EV
## comparison would catch it.
func test_phantom_clamp_reaches_the_finalist_resolve() -> void:
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	var target := _spawn("Target")
	_add_edge(source, joint)
	_add_edge(joint, tip)
	source.global_position = Vector2.ZERO
	joint.global_position = Vector2(60.0, 0.0)
	# Coincident with tip's authored position (mirrors
	# test_gather_melee_candidates_scores_a_real_hit): guarantees shape overlap
	# at t=0 regardless of swing angle/timing, for both plans identically.
	tip.global_position = Vector2(120.0, 0.0)
	target.global_position = Vector2(120.0, 0.0)
	_alloc.force_allocate(_ai_entity, source)
	_ai_entity.core_location = source
	_alloc.force_allocate(_ai_entity, joint)
	_alloc.force_allocate(_ai_entity, tip)
	_alloc.force_allocate(_hostile, target)
	_hostile.core_location = target
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var members: Array[SkillNode] = [joint, tip]

	var real_plan := MeleeAttackPlan.new()
	real_plan.attacker = _ai_entity
	real_plan.source = source
	real_plan.blade_nodes = members
	var clamp_scene := preload("res://skill_node/addons/clamp_addon.tscn")
	var real_clamp := clamp_scene.instantiate() as ClampAddon
	joint.add_child(real_clamp)
	await get_tree().process_frame
	assert_true(real_plan.is_valid())
	var real_outcome := real_plan.resolve()
	var real_ev := AiCombatScorer.expected_damage(real_outcome, _ai_entity)

	joint.remove_child(real_clamp)
	real_clamp.free()
	await get_tree().process_frame

	var phantom_plan := MeleeAttackPlan.new()
	phantom_plan.attacker = _ai_entity
	phantom_plan.source = source
	phantom_plan.blade_nodes = members
	phantom_plan.ai_phantom_clamp_nodes = [joint]
	assert_true(phantom_plan.is_valid())
	var phantom_outcome := phantom_plan.resolve()
	var phantom_ev := AiCombatScorer.expected_damage(phantom_outcome, _ai_entity)

	assert_almost_eq(phantom_ev, real_ev, 0.001,
			"a phantom clamp must reach resolve() and produce the identical swing a real " +
			"ClampAddon would, not the unclamped one build_blade_state alone would give the coarse tier")



# ── _coarse_rank_and_select: the WorkerThreadPool tier actually filters ─────

## Fixtures elsewhere in this file have <= _FINALIST_COUNT proposals, so every
## proposal trivially becomes a finalist and the coarse-rank tier is never
## exercised. This drives it directly with more candidates than finalist
## slots, so a farther one MUST be dropped for the assertion to pass.
func test_coarse_rank_selects_the_nearer_finalists() -> void:
	var pivot := _spawn("Pivot")
	var m_a := _spawn("A")
	var m_b := _spawn("B")
	var m_c := _spawn("C")
	var m_d := _spawn("D")
	pivot.global_position = Vector2.ZERO
	var enemy_pos := Vector2(300.0, 0.0)
	# No owned-territory edges are wired for these — build_blade_state's
	# induced-edge lookup comes back empty, so BladeSim drives no arc and
	# each particle sits at its authored position for the whole coarse
	# "swing": closest-approach reduces to plain distance-to-enemy, letting
	# this test control ranking precisely without needing real swing geometry.
	m_a.global_position = enemy_pos
	m_b.global_position = enemy_pos + Vector2(50.0, 0.0)
	m_c.global_position = enemy_pos + Vector2(100.0, 0.0)
	m_d.global_position = enemy_pos + Vector2(700.0, 0.0)

	var chain_d: Array[SkillNode] = [m_d]
	var chain_a: Array[SkillNode] = [m_a]
	var chain_c: Array[SkillNode] = [m_c]
	var chain_b: Array[SkillNode] = [m_b]
	# A proposal carries its swing direction as its third element (#692
	# follow-up) and its phantom clamp targets as its fourth (#823). These
	# four sit at fixed positions with no arc driving them and no clamps, so
	# direction/clamps are inert here — the ranking under test is the distance one.
	var proposals := [
		[pivot, chain_d, false, [] as Array[SkillNode]], [pivot, chain_a, false, [] as Array[SkillNode]],
		[pivot, chain_c, false, [] as Array[SkillNode]], [pivot, chain_b, false, [] as Array[SkillNode]]]
	var enemy_positions: Array[Vector2] = [enemy_pos]
	var finalists := AiBladeRollout._coarse_rank_and_select(proposals, _ai_entity, enemy_positions)

	assert_eq(finalists.size(), 3, "_FINALIST_COUNT caps the survivors below the 4 proposals given")
	var kept: Array[SkillNode] = []
	for f in finalists:
		kept.append(f[1][0])
	assert_true(kept.has(m_a), "closest candidate must survive coarse ranking")
	assert_true(kept.has(m_b), "second-closest candidate must survive coarse ranking")
	assert_true(kept.has(m_c), "third-closest candidate must survive coarse ranking")
	assert_false(kept.has(m_d), "farthest candidate must be dropped by coarse ranking, not kept by luck")


# ── Full pipeline: pivot prune -> proposals -> coarse rank -> full resolve ──

func test_gather_melee_candidates_scores_a_real_hit() -> void:
	var pivot := _spawn("Pivot")
	var member := _spawn("Member")
	var target := _spawn("Target")
	_add_edge(pivot, member)
	pivot.global_position = Vector2.ZERO
	# Member sweeps a circle of this radius around the pivot; placing the
	# target AT that same point guarantees shape overlap at t=0 regardless
	# of physics-server sync timing, rather than depending on the swing
	# reaching a particular angle by a particular frame.
	member.global_position = Vector2(60.0, 0.0)
	target.global_position = Vector2(60.0, 0.0)

	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, member)
	_alloc.force_allocate(_hostile, target)
	_hostile.core_location = target
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var visible: Array[SkillNode] = [target]
	var started := Time.get_ticks_msec()
	var candidates := AiBladeRollout.gather_melee_candidates(_ai_entity, visible, 0)
	var elapsed := Time.get_ticks_msec() - started

	assert_lt(elapsed, 5000, "rollout must complete in bounded time (no infinite MCMC)")
	assert_gt(candidates.size(), 0, "a valid pivot + induced subgraph exists -> at least one candidate")
	for c in candidates:
		assert_eq(c.mode, BattleSystem.AttackMode.MELEE)
		# Either owned node is a legitimate pivot here (both sit adjacent to
		# the target-coincident point) — the acceptance bar is "the swing
		# actually connects", not which of the two symmetric picks won.
		assert_true(c.source_node == pivot or c.source_node == member,
				"pivot must be one of the AI's own owned nodes")
	var best: AiCombatScorer.ScoredCandidate = AiCombatScorer.pick_best(candidates)
	assert_gt(best.ev, 0.0, "the best candidate should register real damage on the coincident target")


func test_gather_melee_candidates_empty_without_visible_enemy() -> void:
	var pivot := _spawn("Pivot")
	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	await get_tree().process_frame
	var empty: Array[SkillNode] = []
	var candidates := AiBladeRollout.gather_melee_candidates(_ai_entity, empty, 0)
	assert_eq(candidates.size(), 0)


# ── Shape-risk: popped_nodes is a REAL pop count, tier-gated end to end ────

## #378 acceptance: "Shape-risk tier-gated ... ai_tier=1 does [penalize]".
## test_ai_combat_scorer.gd already covers this at the scorer-unit level with
## a synthetic popped_nodes; this is the full-loop version the slice B
## comment flagged as pending — a real defensive-spike pop, produced by an
## actual rollout candidate's resolve(), flowing into the tier-gated penalty.
func test_shape_risk_reflects_a_real_pop_and_is_tier_gated() -> void:
	var pivot := _spawn("Pivot")
	var member := _spawn("Member")
	var target := _spawn("Target")
	_add_edge(pivot, member)
	pivot.global_position = Vector2.ZERO
	member.global_position = Vector2(60.0, 0.0)
	target.global_position = Vector2(60.0, 0.0)

	_alloc.force_allocate(_ai_entity, pivot)
	_ai_entity.core_location = pivot
	_alloc.force_allocate(_ai_entity, member)
	_alloc.force_allocate(_hostile, target)
	_hostile.core_location = target

	# Defensive spike on the target: whichever blade vertex sweeps into it
	# pops (see BladePopResolver / test_spike_pop.gd's fixture pattern).
	var spike_scene := preload("res://skill_node/addons/spike_ring_addon.tscn")
	var spike := spike_scene.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	spike.local_modifiers = [mod]
	target.add_child(spike)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var visible: Array[SkillNode] = [target]
	var naive := AiBladeRollout.gather_melee_candidates(_ai_entity, visible, 0)
	var smart := AiBladeRollout.gather_melee_candidates(_ai_entity, visible, 1)

	var risky_smart := _find_popped(smart)
	assert_not_null(risky_smart, "the connecting swing should have popped a vertex")
	assert_gt(risky_smart.outcome.popped_nodes, 0, "a real pop, not a synthetic count")
	assert_gt(risky_smart.self_shape_risk, 0.0, "ai_tier=1 penalizes a real pop")

	var risky_naive := _find_matching(naive, risky_smart)
	assert_not_null(risky_naive, "the same physical swing should surface at ai_tier=0 too")
	assert_gt(risky_naive.outcome.popped_nodes, 0, "the pop itself doesn't depend on ai_tier")
	assert_almost_eq(risky_naive.self_shape_risk, 0.0, 0.001, "ai_tier=0 never penalizes shape risk")


func _find_popped(candidates: Array[AiCombatScorer.ScoredCandidate]) -> AiCombatScorer.ScoredCandidate:
	for c in candidates:
		if c.outcome != null and c.outcome.popped_nodes > 0:
			return c
	return null


func _find_matching(
		candidates: Array[AiCombatScorer.ScoredCandidate],
		reference: AiCombatScorer.ScoredCandidate) -> AiCombatScorer.ScoredCandidate:
	for c in candidates:
		if c.source_node == reference.source_node and c.blade_nodes == reference.blade_nodes:
			return c
	return null
