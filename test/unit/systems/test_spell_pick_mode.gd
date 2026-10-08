extends GutTest

## [SpellPickMode] (#1484): the spell picker as an [ArmedStack] leaf over
## [MagicMode] / [TargetMode]. The first magic arm with no sticky spell opens
## it; a pick, a hotkey spell write, a graph click, a pop or a launch closes it.
## See docs/domain/click-grammar.md.
##
## Board: Pivot - Joint - Tip owned by the attacker; Hostile adjacent to Tip,
## Far adjacent to Hostile, both owned by an NPC.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _ctl: PlayerInputController
var _attacker: Entity
var _pivot: SkillNode
var _joint: SkillNode
var _tip: SkillNode
var _enemy: SkillNode
var _far: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = pos
	_graph.add_skill_node(sn)
	return sn


func _entity(faction: Faction) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_pivot = _spawn("Pivot", Vector2(0, 0))
	_joint = _spawn("Joint", Vector2(200, 0))
	_tip = _spawn("Tip", Vector2(400, 0))
	_enemy = _spawn("Hostile", Vector2(450, 0))
	_far = _spawn("Far", Vector2(600, 0))
	_graph.add_edge(_pivot, _joint)
	_graph.add_edge(_joint, _tip)
	_graph.add_edge(_tip, _enemy)
	_graph.add_edge(_enemy, _far)
	_attacker = _entity(_PLAYER_FACTION)
	var hostile := _entity(_NPC_FACTION)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	for n in [_pivot, _joint, _tip]:
		_alloc.force_allocate(_attacker, n)
	_alloc.force_allocate(hostile, _enemy)
	_alloc.force_allocate(hostile, _far)
	_tm = TurnManager.new()
	add_child_autofree(_tm)
	_tm.start_turn(_attacker)
	_bs = BattleSystem.new()
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)
	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.turn_manager = _tm
	_ctl.battle_system = _bs
	_ctl.player = _attacker
	add_child_autofree(_ctl)


func _branch() -> Array:
	return _ctl.armed_stack.branch().map(func(m: ArmedMode) -> Script: return m.get_script())


func _melee() -> MeleeAttackPlan:
	return _ctl.armed_stack.attack_plan() as MeleeAttackPlan


func _upgrade() -> PackedScene:
	return preload("res://test/fixtures/addons/second_dot_addon.tscn")


func _heal_spell() -> SpellDef:
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.MINE
	var spell := SpellDef.new()
	spell.targeting = t
	spell.min_degree = 0
	return spell


func _magic() -> MagicAttackPlan:
	return _ctl.armed_stack.attack_plan() as MagicAttackPlan


func _picker() -> SpellPickMode:
	return _ctl.armed_stack.find(SpellPickMode) as SpellPickMode


func _hostile_only_spell() -> SpellDef:
	var spell := _heal_spell()
	(spell.targeting as NodeTargeting).ownership_filter = SkillNode.Ownership.HOSTILE
	return spell


## Arms magic with a sticky spell, then opens the picker on demand.
func _arm_with_picker(spell: SpellDef) -> void:
	_ctl.armed_stack.selected_spell = spell
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	assert_true(_magic_level().toggle_picker(), "precondition: the picker opens")


func _magic_level() -> MagicMode:
	return _ctl.armed_stack.find(MagicMode) as MagicMode


func test_first_arm_with_no_spell_opens_the_picker() -> void:
	assert_null(_ctl.armed_stack.selected_spell, "precondition")
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MAGIC))
	assert_eq(_branch(), [ManageMode, MagicMode, SpellPickMode])


func test_arm_with_a_sticky_spell_lands_on_magic() -> void:
	_ctl.armed_stack.selected_spell = _heal_spell()
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MAGIC))
	assert_eq(_branch(), [ManageMode, MagicMode])


func test_pick_selects_the_spell_and_closes_the_picker() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	var spell := _heal_spell()
	_picker().pick(spell)
	assert_eq(_ctl.armed_stack.selected_spell, spell)
	assert_eq(_magic().spell, spell, "the plan is re-equipped")
	assert_eq(_branch(), [ManageMode, MagicMode], "the picker is off the branch")


func test_picking_the_selected_spell_still_closes_the_picker() -> void:
	var spell := _heal_spell()
	_arm_with_picker(spell)
	_picker().pick(spell)
	assert_eq(_branch(), [ManageMode, MagicMode])
	assert_eq(_magic().spell, spell)


func test_a_hotkey_spell_write_closes_the_picker() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_ctl.armed_stack.selected_spell = _heal_spell()
	assert_eq(_branch(), [ManageMode, MagicMode])


func test_a_graph_click_closes_the_picker_then_targets() -> void:
	_arm_with_picker(_heal_spell())
	_ctl.route_left_click(_joint)
	assert_null(_picker(), "no picker on the branch")
	assert_eq(_branch(), [ManageMode, MagicMode, TargetMode], "the click went through to Magic")
	assert_eq(_magic().target, _joint)


func test_a_graph_click_over_target_closes_the_picker_then_retargets() -> void:
	_ctl.armed_stack.selected_spell = _heal_spell()
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_ctl.route_left_click(_joint)
	assert_true(_magic_level().toggle_picker(), "precondition")
	_ctl.route_left_click(_tip)
	assert_eq(_branch(), [ManageMode, MagicMode, TargetMode])
	assert_eq(_magic().target, _tip)


func test_a_pop_removes_only_the_picker() -> void:
	var spell := _heal_spell()
	_ctl.armed_stack.selected_spell = spell
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_ctl.route_left_click(_joint)
	assert_true(_magic_level().toggle_picker(), "precondition")
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode, MagicMode, TargetMode])
	assert_eq(_magic().spell, spell, "the spell is untouched")
	assert_eq(_magic().target, _joint, "the target is untouched")


func test_a_pick_that_drops_the_target_cascades_cleanly() -> void:
	_ctl.armed_stack.selected_spell = _heal_spell()
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_ctl.route_left_click(_joint)
	assert_true(_magic_level().toggle_picker(), "precondition")
	_picker().pick(_hostile_only_spell())
	assert_null(_magic().target, "precondition: the swap dropped the target")
	assert_eq(_branch(), [ManageMode, MagicMode])


func test_toggle_twice_returns_to_the_start_one_changed_each() -> void:
	_ctl.armed_stack.selected_spell = _heal_spell()
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	watch_signals(_ctl.armed_stack)
	assert_true(_magic_level().toggle_picker(), "the first toggle opens")
	assert_signal_emit_count(_ctl.armed_stack, "changed", 1)
	assert_eq(_branch(), [ManageMode, MagicMode, SpellPickMode])
	assert_false(_magic_level().toggle_picker(), "the second toggle closes")
	assert_signal_emit_count(_ctl.armed_stack, "changed", 2)
	assert_eq(_branch(), [ManageMode, MagicMode])


func test_the_picker_badge_is_the_magic_levels() -> void:
	_arm_with_picker(_heal_spell())
	var magic := _magic_level()
	assert_eq(_picker().tint(), magic.tint())
	assert_eq(_picker().icon(), magic.icon())
	assert_eq(_picker().icon_tint(), magic.icon_tint())


func test_after_a_launch_the_rearmed_plan_stands_with_no_picker() -> void:
	_arm_with_picker(SpellCatalog.SPARK)
	_ctl.route_left_click(_enemy)
	assert_true(_magic().is_valid(), "precondition: %s" % str(_magic().validate()))
	await _bs.launch_attack(_magic())
	await get_tree().process_frame
	assert_eq(_branch(), [ManageMode, MagicMode], "Magic stays armed, no picker")
	assert_not_null(_magic(), "with a fresh magic plan")
	assert_null(_magic().target if _magic() != null else null, "the fresh plan is empty")


func test_a_launch_with_the_picker_open_pops_it() -> void:
	_ctl.armed_stack.selected_spell = SpellCatalog.SPARK
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	# Aimed without the click, so no TargetMode stands between: a TargetMode
	# would pop on the launch and take the picker with it.
	assert_true(_magic_level().set_target(_enemy), "precondition")
	assert_true(_magic_level().toggle_picker(), "precondition")
	assert_eq(_branch(), [ManageMode, MagicMode, SpellPickMode], "precondition")
	assert_true(_magic().is_valid(), "precondition: %s" % str(_magic().validate()))
	await _bs.launch_attack(_magic())
	await get_tree().process_frame
	assert_null(_picker(), "the launch popped the picker")
	assert_eq(_branch(), [ManageMode, MagicMode])
