extends GutTest

## `dune_addon.tscn` — Blindness x Addon. On the map it grants its owner +1
## `blindness_aspect`; on a blade every contact lands Blindness folded through
## the carrier's local `blindness_stacks_per_hit` (+1 per allocation level, +1
## more at 3/X), and a [SplashEffect] (no centre, hop 1, the hit's own mask)
## puffs the same full stacks onto each neighbour of the struck node, at every
## level.
##
## Fixture: test_ashfall_addon.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc with two hostile neighbours (camp, ward) —
## plus the attacker's own node and a neutral node beside the plate, and a
## hostile node two hops out (beyond the camp).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DUNE_PATH := "res://skill_node/addons/defs/dune_addon.tscn"
const _BLINDNESS := preload("res://effects/status/blindness.tres")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

const _SPACING := 150.0
const _TURNS := 0.15

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _plate: SkillNode
var _camp: SkillNode
var _ward: SkillNode
var _mine: SkillNode
var _wild: SkillNode
var _far: SkillNode
var _dune_on_tip := false


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity() -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	_graph.add_child(entity)
	return entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_attacker = _make_entity()
	_defender = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"dune_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	var plate_at := Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0
	_plate = _spawn("Plate", plate_at)
	_camp = _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_ward = _spawn("Ward", plate_at + Vector2(0.0, _SPACING * 3.0))
	_mine = _spawn("Mine", plate_at + Vector2(_SPACING * 2.0, _SPACING * 2.0))
	_wild = _spawn("Wild", plate_at + Vector2(-_SPACING * 2.0, _SPACING * 1.0))
	_far = _spawn("Far", Vector2(-_SPACING * 6.0, _SPACING * 6.0))
	_graph.add_edge(_camp, _plate)
	_graph.add_edge(_camp, _ward)
	_graph.add_edge(_ward, _plate)
	_graph.add_edge(_mine, _plate)
	_graph.add_edge(_wild, _plate)
	_graph.add_edge(_far, _camp)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_alloc.force_allocate(_attacker, _mine)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _camp)
	_defender.core_location = _camp
	_alloc.force_allocate(_defender, _plate)
	_alloc.force_allocate(_defender, _ward)
	_alloc.force_allocate(_defender, _far)
	_mid.add_child(_CLAMP_SCENE.instantiate())
	_dune_on_tip = false


func _scene() -> PackedScene:
	return load(_DUNE_PATH) as PackedScene


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _plan() -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_mid, _tip]
	return plan


## Dune on the tip (attached once per test), filled to [param level]/X, then
## one real swing resolved on a shadow (the live world untouched).
func _swing_at(level: int) -> AttackOutcome:
	var scene := _scene()
	assert_not_null(scene, "the Dune scene exists")
	if scene == null:
		return AttackOutcome.new()
	if not _dune_on_tip:
		_tip.add_child(scene.instantiate())
		_dune_on_tip = true
	_tip.stake_level = maxi(_tip.stake_level, level)
	_alloc.force_fill(_tip, level)
	await _settle()
	var shadow := CombatWorld.shadow()
	var outcome := _plan().resolve_against(shadow)
	shadow.free_shadow()
	return outcome


## The blindness landings the outcome put on [param node].
func _landings_on(outcome: AttackOutcome, node: SkillNode) -> Array[StatusInstance]:
	var found: Array[StatusInstance] = []
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _BLINDNESS and status.target == node:
			found.append(status)
	return found


## Blindness stacks the outcome landed on [param node], summed; -1 when none.
func _blind_on(outcome: AttackOutcome, node: SkillNode) -> float:
	var landings := _landings_on(outcome, node)
	if landings.is_empty():
		return -1.0
	var sum := 0.0
	for status in landings:
		sum += status.power
	return sum


## The struck plate's stacks at [param level]/X, after asserting the puff
## around it: every hostile neighbour takes the same full stacks, nothing
## else does, and the plate is hit once.
func _assert_puff_at(level: int) -> float:
	var outcome := await _swing_at(level)
	var main := _blind_on(outcome, _plate)
	assert_gt(main, 0.0, "%d/X: the contact blinds the struck node" % level)
	assert_eq(_landings_on(outcome, _plate).size(), 1,
			"%d/X: the struck node is hit once, never by its own puff" % level)
	assert_eq(_blind_on(outcome, _camp), main, "%d/X: the hostile camp takes full stacks" % level)
	assert_eq(_blind_on(outcome, _ward), main, "%d/X: the hostile ward takes full stacks" % level)
	assert_eq(_blind_on(outcome, _mine), -1.0, "%d/X: the attacker's own neighbour takes none" % level)
	assert_eq(_blind_on(outcome, _wild), -1.0, "%d/X: a neutral neighbour takes none" % level)
	assert_eq(_blind_on(outcome, _far), -1.0, "%d/X: a 2-hop hostile takes none" % level)
	return main


func test_a_1_of_x_contact_already_puffs_onto_hostile_neighbours() -> void:
	await _assert_puff_at(1)


func test_a_2_of_x_contact_puffs_full_stacks() -> void:
	await _assert_puff_at(2)


func test_a_3_of_x_contact_puffs_full_stacks() -> void:
	await _assert_puff_at(3)


func test_the_stacks_ladder_with_allocation_and_step_once_more_at_3_of_x() -> void:
	var at := {}
	for level in [1, 2, 3]:
		at[level] = _blind_on(await _swing_at(level), _plate)
	var step: float = at[2] - at[1]
	assert_gt(step, 0.0, "each allocation level adds stacks")
	assert_eq(at[3] - at[2], step + 1.0, "3/X: the ladder step plus the +1 unlock")


func test_a_temp_dune_costs_2_blade_size_and_1_blindness_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	assert_true(SkillNodeAddon.temp_placeable_of(scene))
	var costs := SkillNodeAddon.temp_costs_of(scene)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"blindness_aspect", 0), 1)


func test_allocating_a_dune_node_grants_the_owner_blindness_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"blindness_aspect")
	loose.add_child(scene.instantiate())
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"blindness_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"blindness_aspect"), before + 1.0)
