extends GutTest

## The combat readout shows the swing's number for a hovered node in the active
## melee plan: a temp upgrade folds in as an overlay (never onto the board), so
## the readout asks the plan rather than the bare node.

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ArmingCtl := preload("res://test/fixtures/arming_ctl.gd")
const _READOUT_SCENE := preload("res://ui/hud/combat_readout/combat_readout.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _battle: BattleSystem
var _ctl: PlayerInputController
var _readout: CombatReadout


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	var tm: TurnManager = autofree(TurnManager.new())
	add_child(tm)
	tm.start_turn(_entity)
	_battle = BattleSystem.new()
	_battle.turn_manager = tm
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)
	_ctl = _ArmingCtl.make(self, _graph, _alloc, _battle, tm, _entity)
	_readout = _READOUT_SCENE.instantiate() as CombatReadout
	add_child_autofree(_readout)
	_readout.bind(_battle)
	_readout.set_player(_entity)


func after_each() -> void:
	Events.skill_node_unhovered.emit()


## Source - joint - tip, all allocated; `outside` allocated but not selected.
## Budget 4 leaves room for one spike ring (cost 2) after the two members.
func _setup() -> Dictionary:
	_entity.stat_board.blade_size.base_value = 4.0
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	var outside := _spawn("Outside")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	_graph.add_edge(source, outside)
	await get_tree().process_frame
	for n in [source, joint, tip, outside]:
		_alloc.force_allocate(_entity, n)
	return {"source": source, "joint": joint, "tip": tip, "outside": outside}


## Arm melee through the seat's controller and select source - joint - tip on
## the level's plan.
func _arm_plan(ctx: Dictionary) -> MeleeAttackPlan:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	var plan := _ctl.armed_stack.attack_plan() as MeleeAttackPlan
	plan.set_pivot(ctx.source)
	plan.toggle_member(ctx.joint)
	plan.toggle_member(ctx.tip)
	return plan


func _damage_text() -> String:
	return _readout.get_node("%MeleeCard").get_node("%DamageRow").get_node("%Value").text


func _render(v: Variant) -> String:
	return "%.0f" % float(v)


func test_hovering_a_temp_spiked_member_shows_the_swing_value() -> void:
	var ctx: Dictionary = await _setup()
	var joint: SkillNode = ctx.joint
	var plan := _arm_plan(ctx)
	assert_true(plan.apply_temp_upgrade(joint, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	Events.skill_node_hovered.emit(joint)
	var swing: Variant = plan.swing_value(joint, &"blade_damage")
	assert_not_null(swing, "a member has a swing view")
	assert_gt(float(swing), float(joint.get_local_value(&"blade_damage")),
			"the temp spike folds into the swing, not the bare node")
	assert_eq(_damage_text(), _render(swing), "the readout shows the swing's number")


func test_a_node_outside_the_plan_shows_what_it_shows_today() -> void:
	var ctx: Dictionary = await _setup()
	var outside: SkillNode = ctx.outside
	Events.skill_node_hovered.emit(outside)
	var before := _damage_text()
	var plan := _arm_plan(ctx)
	assert_true(plan.apply_temp_upgrade(ctx.joint, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	assert_null(plan.swing_value(outside, &"blade_damage"), "off the plan: no swing view")
	Events.skill_node_hovered.emit(outside)
	assert_eq(_damage_text(), before, "an off-plan node reads as it did with no plan")
	assert_eq(_damage_text(), _render(outside.get_local_value(&"blade_damage")),
			"which is its bare local read")


func test_no_melee_plan_shows_the_bare_local_value() -> void:
	var ctx: Dictionary = await _setup()
	var joint: SkillNode = ctx.joint
	Events.skill_node_hovered.emit(joint)
	var bare := float(joint.get_local_value(&"blade_damage"))
	var baseline := float(_entity.stat_board.get_value(&"blade_damage"))
	assert_eq(_damage_text(), _render(bare if bare != baseline else baseline))


func test_removing_the_temp_upgrade_updates_without_a_rehover() -> void:
	var ctx: Dictionary = await _setup()
	var joint: SkillNode = ctx.joint
	var plan := _arm_plan(ctx)
	assert_true(plan.apply_temp_upgrade(joint, preload("res://skill_node/addons/defs/spike_ring_addon.tscn")))
	Events.skill_node_hovered.emit(joint)
	var spiked := _damage_text()
	plan.remove_temp_upgrade(joint)  # no second hover: attack_plan_state_changed drives it
	var now: Variant = plan.swing_value(joint, &"blade_damage")
	assert_ne(_damage_text(), spiked, "the hovered value moved off the spiked number")
	assert_eq(_damage_text(), _render(now), "and shows the swing's number without the temp")
