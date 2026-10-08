extends GutTest

## The magic body's spell picker (#1485): the spell bar floats in %PickerPanel
## above the body, shown iff [SpellPickMode] is on the seat's [ArmedStack]; the
## body itself shows the equipped spell as one collapsed %SpellButton that
## toggles the picker. Bound over a real controller + stack, the way
## test_click_grammar.gd builds one.

const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")
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
var _body: MagicBody
var _spells: Array[SpellDef] = []


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
	_spells.clear()
	for i in 3:
		var spell := _spell("Spell %d" % i)
		_spells.append(spell)
		_attacker.get_spellbook().learn(spell)
	_body = _BODY_SCENE.instantiate() as MagicBody
	add_child_autofree(_body)
	_body.position = Vector2(0, 400)
	_body.size = Vector2(930, _body.get_combined_minimum_size().y)
	_body.bind(_attacker, _bs, _ctl)


func after_each() -> void:
	if is_instance_valid(_body):
		_body.teardown()


func _spell(nm: String) -> SpellDef:
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.MINE
	var spell := SpellDef.new()
	spell.name = nm
	spell.targeting = t
	spell.min_degree = 0
	return spell


func _panel() -> Control:
	return _body.get_node("%PickerPanel") as Control


func _button() -> SpellPickerButton:
	return _body.get_node("%SpellButton") as SpellPickerButton


func _tile(spell: SpellDef) -> SpellPickerButton:
	for child in _body.get_node("%SpellPickerBar").get_children():
		if child is SpellPickerButton and (child as SpellPickerButton).spell == spell:
			return child as SpellPickerButton
	return null


func _picker_up() -> bool:
	return _ctl.armed_stack.find(SpellPickMode) != null


## Magic armed on a sticky spell, so the arm lands with no picker (#1484).
func _arm() -> void:
	_ctl.armed_stack.selected_spell = _spells[0]
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MAGIC), "precondition: magic armed")
	assert_false(_picker_up(), "precondition: no picker")


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_spell_button_toggles_the_picker_and_the_panel() -> void:
	_arm()
	assert_false(_panel().visible, "no picker level, no panel")
	_button().pressed.emit()
	assert_true(_picker_up(), "the press pushes the picker")
	assert_true(_panel().visible, "and shows the panel")
	_button().pressed.emit()
	assert_false(_picker_up(), "a second press pops it")
	assert_false(_panel().visible, "and hides the panel")


func test_a_tile_press_picks_closes_and_relabels_the_button() -> void:
	_arm()
	assert_eq(_button().spell, _spells[0], "precondition: the button shows the equipped spell")
	_button().pressed.emit()
	var tile := _tile(_spells[2])
	assert_not_null(tile, "precondition: the open bar has the tile")
	tile.pressed.emit()
	assert_eq(_ctl.armed_stack.selected_spell, _spells[2], "the tile picked its spell")
	assert_false(_picker_up(), "the pick closed the picker")
	assert_false(_panel().visible, "and hid the panel")
	assert_eq(_button().spell, _spells[2], "the button shows the new spell")


func test_right_click_with_the_panel_open_hides_it() -> void:
	_arm()
	_button().pressed.emit()
	assert_true(_panel().visible, "precondition")
	assert_true(_ctl.pop_armed_level())
	assert_false(_panel().visible)


func test_the_panel_never_moves_the_body_min_size() -> void:
	_arm()
	await _settle()
	var hidden := _body.get_combined_minimum_size()
	_button().pressed.emit()
	await _settle()
	assert_true(_panel().visible, "precondition")
	assert_eq(_body.get_combined_minimum_size(), hidden, "shown or hidden, the panel adds nothing")


func test_the_panel_sits_on_the_body_top_edge() -> void:
	_arm()
	_button().pressed.emit()
	await _settle()
	var panel := _panel().get_global_rect()
	var body := _body.get_global_rect()
	assert_almost_eq(panel.end.y, body.position.y - _body.picker_gap_px, 0.5, "bottom edge one gap above the body")
	assert_gt(panel.size.y, 0.0, "the panel grows upward with content")
