extends GutTest

## `ashfall_addon.tscn` — Wither x Addon. On the map it grants its owner +1
## `wither_aspect`; on a blade every contact lands Wither folded through the
## carrier's local `wither_stacks_per_hit` (+1 per allocation level, x2 at
## 3/X), and a [SplashEffect] (no centre, hop 1, the hit's own mask) lands a
## share of it on each neighbour of the struck node: the spread needs no kill.
##
## Fixture: test_doombrand_addon.gd's spine — pivot, mid, tip in a line, a
## hostile plate on the tip's arc with two hostile neighbours (camp, ward) —
## plus a node of the attacker's own beside the plate.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ASHFALL_PATH := "res://skill_node/addons/defs/ashfall_addon.tscn"
const _WITHER := preload("res://effects/status/wither.tres")
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
	enemy_camp.id = &"ashfall_enemy"
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
	_graph.add_edge(_camp, _plate)
	_graph.add_edge(_camp, _ward)
	_graph.add_edge(_ward, _plate)
	_graph.add_edge(_mine, _plate)
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
	_mid.add_child(_CLAMP_SCENE.instantiate())


func _scene() -> PackedScene:
	return load(_ASHFALL_PATH) as PackedScene


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


## Ashfall on the tip, filled to [param level]/X, then one real swing resolved
## on a shadow (the live world untouched).
func _swing_at(level: int) -> AttackOutcome:
	var scene := _scene()
	assert_not_null(scene, "the Ashfall scene exists")
	if scene == null:
		return AttackOutcome.new()
	_tip.add_child(scene.instantiate())
	_tip.stake_level = maxi(_tip.stake_level, level)
	_alloc.force_fill(_tip, level)
	await _settle()
	var shadow := CombatWorld.shadow()
	var outcome := _plan().resolve_against(shadow)
	shadow.free_shadow()
	return outcome


## Wither stacks the outcome landed on [param node], summed; -1 when none.
func _wither_on(outcome: AttackOutcome, node: SkillNode) -> float:
	var sum := -1.0
	for hit in outcome.hits:
		var status := hit as StatusInstance
		if status != null and status.def == _WITHER and status.target == node:
			sum = maxf(sum, 0.0) + status.power
	return sum


## The authored splash on the scene's on-hit list.
func _splash() -> SplashEffect:
	var scene := _scene()
	if scene == null:
		return null
	var addon := scene.instantiate() as SkillNodeAddon
	var found: SplashEffect = null
	for e in addon.on_hit_effects:
		if e is SplashEffect:
			found = e
	addon.free()
	return found


func test_a_2_of_x_contact_withers_the_target_and_a_share_spreads_to_its_hostile_neighbours() -> void:
	var outcome := await _swing_at(2)
	var main := _wither_on(outcome, _plate)
	assert_eq(main, 2.0, "2/X: +1 stack per allocation level on the contact")
	var splash := _splash()
	assert_not_null(splash, "the spread is a SplashEffect")
	if splash == null:
		return
	assert_false(splash.hits_centre, "the centre takes only the main rider")
	var share := StatusDef.round_half_up(main * splash.stack_scale)
	assert_lt(share, main, "a neighbour takes a share, never the full amount")
	assert_eq(_wither_on(outcome, _camp), share, "the hostile camp takes its share")
	assert_eq(_wither_on(outcome, _ward), share, "the hostile ward takes its share")
	assert_eq(_wither_on(outcome, _mine), -1.0, "the attacker's own neighbour takes none")


func test_a_3_of_x_contact_doubles_through_the_unlock() -> void:
	var outcome := await _swing_at(3)
	var main := _wither_on(outcome, _plate)
	assert_eq(main, 6.0, "3/X: three stacks, x2 at the unlock")
	var splash := _splash()
	if splash != null:
		assert_eq(_wither_on(outcome, _ward), StatusDef.round_half_up(main * splash.stack_scale))


func test_a_temp_ashfall_costs_2_blade_size_and_1_wither_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	assert_true(SkillNodeAddon.temp_placeable_of(scene))
	var costs := SkillNodeAddon.temp_costs_of(scene)
	assert_eq(costs.get(&"blade_size", 0), 2)
	assert_eq(costs.get(&"wither_aspect", 0), 1)


func test_allocating_an_ashfall_node_grants_the_owner_wither_aspect() -> void:
	var scene := _scene()
	assert_not_null(scene)
	if scene == null:
		return
	var loose := _spawn("Loose", Vector2(0.0, _SPACING * 3.0))
	var before: float = _attacker.stat_board.get_value(&"wither_aspect")
	loose.add_child(scene.instantiate())
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"wither_aspect"), before,
			"unallocated: the modifier waits on the node")
	_alloc.force_allocate(_attacker, loose)
	await get_tree().process_frame
	assert_eq(_attacker.stat_board.get_value(&"wither_aspect"), before + 1.0)
