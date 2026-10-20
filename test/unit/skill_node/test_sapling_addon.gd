extends GutTest

## `sapling_addon.tscn` — Weakness x Addon. On the map it grants its owner +1
## `weakness_aspect`; on a blade every contact lands Weakness folded through
## the carrier's local `weakness_stacks_per_hit` (+1 per allocation level,
## ×2 at 3/X). A weakened node's own outgoing blade damage drops, and never
## below the owner's cap of 0.1 × unweakened however many stacks land.
##
## Fixture: test_compromiser_addon.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc, a Clamp on the mid.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SAPLING_PATH := "res://skill_node/addons/defs/sapling_addon.tscn"
const _WEAKENED := preload("res://effects/status/weakened.tres")
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
var _sapling_on_tip := false


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
	enemy_camp.id = &"sapling_enemy"
	_defender.faction = enemy_camp

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	_plate = _spawn("Plate", Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _mid)
	_alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _plate)
	_mid.add_child(_CLAMP_SCENE.instantiate())
	_sapling_on_tip = false


func _scene() -> PackedScene:
	return load(_SAPLING_PATH) as PackedScene


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


## Sapling on the tip (attached once per test), filled to [param level]/X,
## then one real swing resolved on a shadow (the live world untouched).
func _swing_at(level: int) -> AttackOutcome:
	var scene := _scene()
	assert_not_null(scene, "the Sapling scene exists")
	if scene == null:
		return AttackOutcome.new()
	if not _sapling_on_tip:
		_tip.add_child(scene.instantiate())
		_sapling_on_tip = true
	_tip.stake_level = maxi(_tip.stake_level, level)
	_alloc.force_fill(_tip, level)
	await _settle()
	var shadow := CombatWorld.shadow()
	var outcome := _plan().resolve_against(shadow)
	shadow.free_shadow()
	return outcome


## Weakness stacks the outcome landed on the plate, summed; -1 when none.
func _weakness_on_plate(outcome: AttackOutcome) -> float:
	var sum := -1.0
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _WEAKENED and status.target == _plate:
			sum = maxf(sum, 0.0) + status.power
	return sum


func test_a_2_of_x_contact_lands_its_weakness() -> void:
	assert_eq(_weakness_on_plate(await _swing_at(2)), 2.0)


func test_a_3_of_x_contact_lands_doubled_weakness() -> void:
	assert_eq(_weakness_on_plate(await _swing_at(3)), 6.0)


func test_the_weakened_nodes_blade_damage_drops_and_floors_at_a_tenth() -> void:
	var plain: float = _plate.get_local_value(&"blade_damage")
	assert_gt(plain, 0.0, "precondition: the plate deals blade damage")
	var landed := _weakness_on_plate(await _swing_at(2))
	_plate.get_combat().apply_status(_WEAKENED, landed)
	assert_lt(_plate.get_local_value(&"blade_damage"), plain,
			"a Sapling contact's stacks cut the struck node's blade damage")
	_plate.get_combat().apply_status(_WEAKENED, 1000.0)
	assert_almost_eq(_plate.get_local_value(&"blade_damage"), plain * 0.1, 0.0001,
			"however many stacks land, the cut stops at 0.1 × (the owner's cap)")


func test_a_temp_sapling_costs_2_blade_size_and_1_weakness_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	assert_true(SkillNodeAddon.temp_placeable_of(scene))
	var costs := SkillNodeAddon.temp_costs_of(scene)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"weakness_aspect", 0), 1)


func test_allocating_a_sapling_node_grants_the_owner_weakness_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"weakness_aspect")
	loose.add_child(scene.instantiate())
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"weakness_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"weakness_aspect"), before + 1.0)
