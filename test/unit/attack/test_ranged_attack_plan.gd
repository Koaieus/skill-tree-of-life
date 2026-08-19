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


func test_resolve_stamps_launch_stagger_onto_arrival_time() -> void:
	# resolve() records the FULL time from volley start to impact: each hit's
	# arrival_time = its own launch offset (index * LAUNCH_STAGGER) + its
	# distance/speed flight. A replay reconstructs the whole volley schedule
	# from outcome.hits alone — no VFX-layer secret. Both leaves reach here.
	_set_range(_leaf_far, 500.0)  # distance 450 → reaches too
	var p := _plan()
	p._on_node_left_clicked(_target)
	var outcome := p.resolve()
	assert_eq(outcome.hits.size(), 2)
	var hit0: DamageInstance = outcome.hits[0]
	var hit1: DamageInstance = outcome.hits[1]
	var d0 := hit0.origin.global_position.distance_to(_target.global_position)
	var d1 := hit1.origin.global_position.distance_to(_target.global_position)
	assert_almost_eq(hit0.arrival_time, d0 / RangedDamageFormula.PROJECTILE_SPEED, 0.001,
			"shot 0 launches at t=0 — no stagger")
	assert_almost_eq(hit1.arrival_time - hit0.arrival_time,
			(d1 - d0) / RangedDamageFormula.PROJECTILE_SPEED
					+ RangedDamageFormula.LAUNCH_STAGGER, 0.001,
			"shot 1 arrives LAUNCH_STAGGER later than pure flight would give")


func test_resolve_on_invalid_plan_returns_empty_outcome() -> void:
	var p := _plan()
	assert_true(p.resolve().hits.is_empty())
