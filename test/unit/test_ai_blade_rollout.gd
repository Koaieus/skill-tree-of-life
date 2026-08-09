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


# ── _greedy_chain: steers toward the target, bounded by max_size ───────────

func test_greedy_chain_picks_nearer_neighbour_first() -> void:
	var pivot := _spawn("Pivot")
	var near := _spawn("Near")
	var far := _spawn("Far")
	pivot.global_position = Vector2.ZERO
	near.global_position = Vector2(50.0, 0.0)
	far.global_position = Vector2(0.0, 500.0)
	var adjacency := {pivot: [near, far], near: [pivot], far: [pivot]}
	var chain := AiBladeRollout._greedy_chain(pivot, adjacency, Vector2(60.0, 0.0), 2)
	assert_eq(chain.size(), 2)
	assert_eq(chain[0], near, "the neighbour closer to the target is picked first")


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
	var proposals := [[pivot, chain_d], [pivot, chain_a], [pivot, chain_c], [pivot, chain_b]]
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


func test_greedy_chain_stops_when_no_neighbours_left() -> void:
	var pivot := _spawn("Pivot")
	pivot.global_position = Vector2.ZERO
	var adjacency := {pivot: []}
	var chain := AiBladeRollout._greedy_chain(pivot, adjacency, Vector2(100.0, 0.0), 5)
	assert_eq(chain.size(), 0, "no owned neighbours -> empty chain, not an infinite loop")


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


# ── Shape-risk: thinned_nodes is a REAL pop count, tier-gated end to end ────

## #378 acceptance: "Shape-risk tier-gated ... ai_tier=1 does [penalize]".
## test_ai_combat_scorer.gd already covers this at the scorer-unit level with
## a synthetic thinned_nodes; this is the full-loop version the slice B
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

	var risky_smart := _find_thinned(smart)
	assert_not_null(risky_smart, "the connecting swing should have popped a vertex")
	assert_gt(risky_smart.outcome.thinned_nodes, 0, "a real pop, not a synthetic count")
	assert_gt(risky_smart.self_shape_risk, 0.0, "ai_tier=1 penalizes a real pop")

	var risky_naive := _find_matching(naive, risky_smart)
	assert_not_null(risky_naive, "the same physical swing should surface at ai_tier=0 too")
	assert_gt(risky_naive.outcome.thinned_nodes, 0, "the pop itself doesn't depend on ai_tier")
	assert_almost_eq(risky_naive.self_shape_risk, 0.0, 0.001, "ai_tier=0 never penalizes shape risk")


func _find_thinned(candidates: Array[AiCombatScorer.ScoredCandidate]) -> AiCombatScorer.ScoredCandidate:
	for c in candidates:
		if c.outcome != null and c.outcome.thinned_nodes > 0:
			return c
	return null


func _find_matching(
		candidates: Array[AiCombatScorer.ScoredCandidate],
		reference: AiCombatScorer.ScoredCandidate) -> AiCombatScorer.ScoredCandidate:
	for c in candidates:
		if c.source_node == reference.source_node and c.blade_nodes == reference.blade_nodes:
			return c
	return null
