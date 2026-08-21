extends GutTest

## RangedAttackPlan: cost/reach/legality against a real Graph + Entity
## fixture, mirroring test_blade_damage_localization.gd's approach to
## MeleeAttackPlan. Firing positions are the attacker's owned-subgraph
## LEAVES (EntityNavigator.get_leaf_nodes); a leaf only "reaches" a target if
## its own get_local_value(&"range") covers the distance.
##
## Chain A(0,0) - B(200,0) - C(400,0), attacker owns all three: A and C are
## the leaves (degree 1), B is the non-leaf midpoint. Target sits at
## (450, 0) — 50px from C, 450px from A.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _hostile: Entity
var _leaf_far: SkillNode
var _mid: SkillNode
var _leaf_near: SkillNode
var _target: SkillNode


func _set_range(node: SkillNode, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"range"
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _set_ranged_damage(node: SkillNode, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"ranged_damage"
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_leaf_far = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_mid = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_leaf_near = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_leaf_far.position = Vector2(0, 0)
	_mid.position = Vector2(200, 0)
	_leaf_near.position = Vector2(400, 0)
	_graph.add_skill_node(_leaf_far)
	_graph.add_skill_node(_mid)
	_graph.add_skill_node(_leaf_near)
	_graph.add_edge(_leaf_far, _mid)
	_graph.add_edge(_mid, _leaf_near)

	_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_target.position = Vector2(450, 0)
	_graph.add_skill_node(_target)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)

	_hostile = Entity.new()
	_hostile.faction = _NPC_FACTION
	_hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_hostile)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _leaf_far)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _leaf_near)
	_alloc.force_allocate(_hostile, _target)

	autofree(_attacker)
	autofree(_hostile)

	# distance(_leaf_near, _target) = 50; distance(_leaf_far, _target) = 450.
	_set_range(_leaf_near, 100.0)  # reaches
	_set_range(_leaf_far, 100.0)   # does not reach
	_set_ranged_damage(_leaf_near, 12.0)


func _plan() -> RangedAttackPlan:
	var p := RangedAttackPlan.new()
	autofree(p)
	p.attacker = _attacker
	return p


# ── Reach ────────────────────────────────────────────────────────────────

func test_get_firing_positions_returns_owned_leaves_only() -> void:
	var p := _plan()
	var positions := p.get_firing_positions()
	assert_eq(positions.size(), 2)
	assert_true(positions.has(_leaf_far))
	assert_true(positions.has(_leaf_near))
	assert_false(positions.has(_mid))


func test_get_reaching_firing_positions_only_the_leaf_within_range() -> void:
	var p := _plan()
	p._on_node_left_clicked(_target)
	assert_eq(p.get_reaching_firing_positions(), [_leaf_near])


# ── Legality ─────────────────────────────────────────────────────────────

func test_validate_requires_a_target() -> void:
	var p := _plan()
	assert_has(p.validate(), &'No target')
	assert_false(p.is_valid())


func test_validate_rejects_a_non_hostile_target() -> void:
	var p := _plan()
	p.target = _leaf_near  # owned by attacker, bypassing click gating
	assert_has(p.validate(), &'Target node is not owned by an enemy')


func test_validate_rejects_a_target_out_of_every_leafs_range() -> void:
	_set_range(_leaf_near, 1.0)  # no longer reaches (distance 50)
	var p := _plan()
	p._on_node_left_clicked(_target)
	assert_has(p.validate(), &'No firing position can reach target')


func test_validate_passes_with_a_reaching_target() -> void:
	var p := _plan()
	p._on_node_left_clicked(_target)
	assert_eq(p.validate(), [] as Array[String])
	assert_true(p.is_valid())


# ── Cost + resolution ────────────────────────────────────────────────────

func test_resolve_produces_one_hit_per_reaching_firing_position() -> void:
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 1)
	var hit := outcome.hits[0]
	assert_eq(hit.target, _target)
	assert_eq(hit.origin, _leaf_near)
	assert_almost_eq(hit.amount, 12.0, 0.001)


func test_resolve_default_ap_cost_is_one() -> void:
	var p := _plan()
	p._on_node_left_clicked(_target)
	assert_eq(p.resolve().ap_cost, 1)


func test_resolve_stamps_the_authored_ramp_onto_arrival_time() -> void:
	# resolve() authors arrival_time from the volley's DISTANCE SPAN, not from
	# distance/speed and not from append order. The two ends of the span pin
	# the window: the nearest leaf launches at DRAW_TIME (frac 0), the
	# furthest-reaching one DRAW_TIME + TOTAL_STAGGER later (frac 1). Both
	# leaves reach here; _leaf_near (dist 50) outranks _leaf_far (dist 450).
	_set_range(_leaf_far, 500.0)  # distance 450 → reaches too
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 2)
	var near_hit: DamageInstance = outcome.hits[0]
	var far_hit: DamageInstance = outcome.hits[1]
	assert_eq(near_hit.origin, _leaf_near, "nearest leaf fires (and is listed) first")
	assert_eq(far_hit.origin, _leaf_far)
	assert_almost_eq(near_hit.arrival_time,
			RangedDamageFormula.DRAW_TIME + RangedDamageFormula.FLIGHT_TIME, 0.0001,
			"rank 0 launches at DRAW_TIME with no ramp offset")
	assert_almost_eq(far_hit.arrival_time,
			RangedDamageFormula.DRAW_TIME + RangedDamageFormula.TOTAL_STAGGER
					+ RangedDamageFormula.FLIGHT_TIME, 0.0001,
			"the last rank launches TOTAL_STAGGER after the first")


## Attaches a fresh reaching leaf to `_mid` at [param pos]. Returns it so a
## test can name its distance in the assertion it cares about.
func _add_reaching_leaf(pos: Vector2) -> SkillNode:
	var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf.position = pos
	_graph.add_skill_node(leaf)
	_graph.add_edge(leaf, _mid)
	_alloc.force_allocate(_attacker, leaf)
	_set_range(leaf, 1000.0)
	return leaf


func test_middle_shot_launches_at_its_distance_fraction_not_its_rank() -> void:
	# The whole point of the metric ramp, and the ONLY assertion that can tell
	# it apart from the old ordinal one — with 3 shots, rank-lerp would put the
	# middle shot at 0.5 * TOTAL_STAGGER no matter where it stands.
	# Distances to _target(450, 0): near 50, mid_leaf 150, far 450.
	# span 400 → fracs 0, 0.25, 1.
	_set_range(_leaf_far, 500.0)
	_add_reaching_leaf(Vector2(450, 150))
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 3)
	var base: float = RangedDamageFormula.DRAW_TIME + RangedDamageFormula.FLIGHT_TIME
	assert_almost_eq(outcome.hits[0].arrival_time, base, 0.0001,
			"nearest leaf pins frac 0")
	assert_almost_eq(outcome.hits[1].arrival_time,
			base + 0.25 * RangedDamageFormula.TOTAL_STAGGER, 0.0001,
			"a leaf a quarter of the way across the span launches a quarter into it")
	assert_almost_eq(outcome.hits[2].arrival_time,
			base + RangedDamageFormula.TOTAL_STAGGER, 0.0001,
			"furthest leaf pins frac 1")


func test_near_identical_distances_launch_together() -> void:
	# The reason this is a lerp and not a rank: two leaves a hair apart must
	# read as one salvo, not as two evenly spaced slices of the window.
	_set_range(_leaf_far, 500.0)
	_add_reaching_leaf(Vector2(450, 200))    # distance 200
	_add_reaching_leaf(Vector2(450, 200.1))  # distance 200.1
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 4)
	assert_almost_eq(outcome.hits[1].arrival_time, outcome.hits[2].arrival_time,
			0.001, "0.1px apart out of a 400px span is a shared beat")


func test_equidistant_leaves_all_launch_on_the_same_beat() -> void:
	# Degenerate span (d_max == d_min): the division guard. Unguarded this
	# stamps NaN into every arrival_time and fails silently downstream.
	_set_range(_leaf_near, 0.0)  # only the two new leaves fire
	_add_reaching_leaf(Vector2(450, 300))
	_add_reaching_leaf(Vector2(450, -300))
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 2)
	var expected: float = RangedDamageFormula.DRAW_TIME + RangedDamageFormula.FLIGHT_TIME
	for hit in outcome.hits:
		assert_almost_eq(hit.arrival_time, expected, 0.0001,
				"an equidistant volley has no ramp to spread across")


func test_single_shot_volley_launches_at_draw_time() -> void:
	# n == 1 is the other degenerate span — same guard, different cause.
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 1)
	assert_almost_eq(outcome.hits[0].arrival_time,
			RangedDamageFormula.DRAW_TIME + RangedDamageFormula.FLIGHT_TIME, 0.0001)


func test_firing_schedule_ranks_nearest_leaf_first() -> void:
	_set_range(_leaf_far, 500.0)  # distance 450 → reaches too
	var p := _plan()
	p._on_node_left_clicked(_target)
	var schedule := p.get_firing_schedule()
	assert_eq(schedule.size(), 2)
	assert_eq(schedule[0].firing_node, _leaf_near, "distance 50, closest, ranks first")
	assert_eq(schedule[1].firing_node, _leaf_far, "distance 450, ranks last")
	assert_eq(schedule[0].target, _target)


func test_launch_span_equals_arrival_span_at_any_shot_count() -> void:
	# The issue's mechanical payoff for a constant FLIGHT_TIME: launch span
	# and arrival span are identical, so this must hold at both n=2 and n=3.
	_set_range(_leaf_far, 500.0)
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 2)
	var launch_span: float = (outcome.hits[1].arrival_time - RangedDamageFormula.FLIGHT_TIME) \
			- (outcome.hits[0].arrival_time - RangedDamageFormula.FLIGHT_TIME)
	var arrival_span: float = outcome.hits[1].arrival_time - outcome.hits[0].arrival_time
	assert_almost_eq(launch_span, arrival_span, 0.0001)
	assert_almost_eq(arrival_span, RangedDamageFormula.TOTAL_STAGGER, 0.0001,
			"span between the only two ranks is the full TOTAL_STAGGER")


func test_wall_time_is_constant_across_shot_counts() -> void:
	# A 2-shot and a 3-shot volley must cover the same TOTAL_STAGGER window —
	# a larger volley reads as denser, not slower.
	_set_range(_leaf_far, 500.0)
	var two_shot := _plan()
	two_shot._on_node_left_clicked(_target)
	var outcome_two := two_shot.resolve()
	assert_eq(outcome_two.hits.size(), 2)
	var span_two := outcome_two.hits[-1].arrival_time - outcome_two.hits[0].arrival_time

	var mid_leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	mid_leaf.position = Vector2(500, 100)
	_graph.add_skill_node(mid_leaf)
	_graph.add_edge(mid_leaf, _mid)
	_alloc.force_allocate(_attacker, mid_leaf)
	_set_range(mid_leaf, 500.0)
	var three_shot := _plan()
	three_shot._on_node_left_clicked(_target)
	var outcome_three := three_shot.resolve()
	assert_eq(outcome_three.hits.size(), 3)
	var span_three := outcome_three.hits[-1].arrival_time - outcome_three.hits[0].arrival_time

	assert_almost_eq(span_two, RangedDamageFormula.TOTAL_STAGGER, 0.0001)
	assert_almost_eq(span_three, RangedDamageFormula.TOTAL_STAGGER, 0.0001)


func test_reordering_allocation_does_not_change_the_firing_schedule() -> void:
	# The bug this issue fixes: RangedAttackPlan used to derive firing order
	# from GraphMirror._node_ids insertion order, i.e. allocation order.
	# Build the same three-leaf star twice, force_allocate-ing the leaves in
	# opposite sequences, and assert both plans agree on rank (by distance)
	# regardless.
	var forward := await _build_three_leaf_star([0, 1, 2])
	var reversed := await _build_three_leaf_star([2, 1, 0])
	var schedule_a: Array = forward["plan"].get_firing_schedule()
	var schedule_b: Array = reversed["plan"].get_firing_schedule()
	assert_eq(schedule_a.size(), 3)
	assert_eq(schedule_b.size(), 3)
	for i in 3:
		var da: float = schedule_a[i].firing_node.global_position.distance_to(
				forward["target"].global_position)
		var db: float = schedule_b[i].firing_node.global_position.distance_to(
				reversed["target"].global_position)
		assert_almost_eq(da, db, 0.0001, "rank %d must land on the same distance regardless of allocation order" % i)
	var outcome_a: AttackOutcome = forward["plan"].resolve()
	var outcome_b: AttackOutcome = reversed["plan"].resolve()
	for i in 3:
		assert_almost_eq(outcome_a.hits[i].arrival_time, outcome_b.hits[i].arrival_time, 0.0001)


## Builds a fresh core+3-leaf star (leaves at distinct distances from a
## shared target) on its own Graph/Entity, force_allocate-ing the leaves in
## [param leaf_order] (a permutation of [0, 1, 2]). Used to prove firing
## order is independent of allocation order.
func _build_three_leaf_star(leaf_order: Array) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var core := _SKILL_NODE_SCENE.instantiate() as SkillNode
	core.position = Vector2(0, 0)
	graph.add_skill_node(core)
	var offsets := [Vector2(100, 0), Vector2(0, 150), Vector2(-200, -50)]
	var leaves: Array[SkillNode] = []
	for offset in offsets:
		var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
		leaf.position = offset
		graph.add_skill_node(leaf)
		graph.add_edge(core, leaf)
		leaves.append(leaf)
	var target := _SKILL_NODE_SCENE.instantiate() as SkillNode
	target.position = Vector2(1000, 1000)
	graph.add_skill_node(target)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(attacker)
	var hostile := Entity.new()
	hostile.faction = _NPC_FACTION
	hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, core)
	for i in leaf_order:
		alloc.force_allocate(attacker, leaves[i])
	alloc.force_allocate(hostile, target)
	for leaf in leaves:
		_set_range(leaf, 3000.0)

	autofree(attacker)
	autofree(hostile)

	var p := RangedAttackPlan.new()
	autofree(p)
	p.attacker = attacker
	p._on_node_left_clicked(target)
	return {"plan": p, "leaves": leaves, "target": target}


func test_resolve_on_invalid_plan_returns_empty_outcome() -> void:
	var p := _plan()
	assert_true(p.resolve().hits.is_empty())


# ── Land-time gate: overkill duds the rest of the volley (#503) ───────────

## Four firing leaves off `_mid`, all reaching, 4 damage each — the target's
## default 10 node_health dies on the 3rd shot (10 → 6 → 2 → depleted). Shots
## 4.. must land INERT: OutcomeApplier's land-time gate re-checks allocation
## per landing (docs/domain/attack-timeline.md), so the volley must not keep
## applying damage to a node that died mid-flight. Stands in for
## BattleSystem's real depleted→dealloc cascade with a direct
## force_deallocate on the depleted signal, to keep this a pure
## RangedAttackPlan/OutcomeApplier test.
func test_gate_vetoes_shots_after_the_target_dies_mid_volley() -> void:
	var extra_a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var extra_b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	extra_a.position = Vector2(420, 120)
	extra_b.position = Vector2(440, -120)
	_graph.add_skill_node(extra_a)
	_graph.add_skill_node(extra_b)
	_graph.add_edge(_mid, extra_a)
	_graph.add_edge(_mid, extra_b)
	_alloc.force_allocate(_attacker, extra_a)
	_alloc.force_allocate(_attacker, extra_b)
	for leaf in [_leaf_near, extra_a, extra_b, _leaf_far]:
		_set_range(leaf, 600.0)
		_set_ranged_damage(leaf, 4.0)

	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 4, "precondition: all four leaves reach")

	var handler := func(node: SkillNode) -> void:
		if node == _target:
			_alloc.force_deallocate(_target)
	Events.skill_node_depleted.connect(handler)
	OutcomeApplier.apply(outcome)
	Events.skill_node_depleted.disconnect(handler)

	assert_almost_eq(_target.get_current_hp(), 0.0, 0.001,
			"the target must have been depleted by the 3rd shot")
	assert_false(outcome.hits[0].gated, "shot 1 lands normally")
	assert_false(outcome.hits[1].gated, "shot 2 lands normally")
	assert_false(outcome.hits[2].gated, "shot 3 lands normally and kills")
	assert_true(outcome.hits[3].gated, "shot 4 must be vetoed — the target is already dead")
	assert_almost_eq(outcome.hits[3].effective_amount, 0.0, 0.001,
			"a vetoed shot applies no damage")
	assert_eq(outcome.hits[3].target, _target, "a vetoed shot is not re-aimed at another target")
