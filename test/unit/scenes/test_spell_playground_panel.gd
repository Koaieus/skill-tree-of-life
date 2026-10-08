extends GutTest

## The spell playground's control strip: aspect slots that grant the caster
## `<concept>_aspect` caps, a real End turn that ticks statuses, and no core
## presence dressing on its fit-scaled board.

const _PANEL := preload("res://addons/spell_playground/playground_panel.tscn")
const _POISON: StatusDef = preload("res://effects/status/poison.tres")

var _panel: Node
var _graph: Graph
var _caster: Entity
var _defender: Entity


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_graph = _panel.find_child("Graph", true, false) as Graph
	_caster = _panel.find_child("CasterEntity", true, false) as Entity
	_defender = _panel.find_child("DefenderEntity", true, false) as Entity
	_panel._battle.instant_mutation = true


func _node(name_: String) -> SkillNode:
	return _graph.get_node("Nodes/%s" % name_) as SkillNode


func _slots() -> Node:
	return _panel.find_child("AspectSlotsRow", true, false)


func _caps() -> Dictionary:
	var out := {}
	for aspect in AspectRoster.shared().aspects:
		if aspect != null and aspect.stat != null:
			out[aspect.stat.id] = AspectCurrency.cap_of(_caster, aspect.stat.id)
	return out


func test_no_aspect_is_granted_until_slotted() -> void:
	for id in _caps():
		assert_eq(_caps()[id], 0, "%s starts at 0" % id)


func test_a_slotted_aspect_caps_exactly_that_aspect() -> void:
	var row := _slots()
	assert_not_null(row, "the panel instances an AspectSlotsRow")
	if row == null:
		return
	row.set_slot(0, &"poison_aspect", 3)
	var caps := _caps()
	assert_eq(caps[&"poison_aspect"], 3)
	for id in caps:
		if id != &"poison_aspect":
			assert_eq(caps[id], 0, "%s stays 0" % id)
	row.set_slot_count(2)
	row.set_slot(1, &"bleeding_aspect", 1)
	caps = _caps()
	assert_eq(caps[&"poison_aspect"], 3)
	assert_eq(caps[&"bleeding_aspect"], 1)
	row.set_slot_count(1)
	assert_eq(_caps()[&"bleeding_aspect"], 0, "a hidden slot grants nothing")


func test_end_turn_twice_ticks_defender_poison_and_returns_the_turn() -> void:
	var tm: TurnManager = _panel._systems.turn_manager
	assert_eq(tm.current_entity, _caster, "the caster holds the turn at bring-up")
	var target := _node("d_hub")
	target.get_combat().apply_status(_POISON, 3.0)
	var before: float = target.get_combat().get_status_power(&"poison")
	assert_gt(before, 0.0, "fixture: poison landed")
	var button := _panel.find_child("EndTurnButton", true, false) as Button
	assert_not_null(button, "HeaderRow carries an EndTurnButton")
	if button == null:
		return
	button.pressed.emit()
	assert_eq(tm.current_entity, _defender, "one click hands the turn to the defender")
	assert_true(_panel.cast_button.disabled, "Cast is off while the defender holds the turn")
	button.pressed.emit()
	assert_eq(target.get_combat().get_status_power(&"poison"), before - 1.0,
			"the defender's turn end ticked its node's poison once")
	assert_eq(tm.current_entity, _caster, "and the turn is back with the caster")


func test_turn_manager_is_scoped_to_the_playground_graph() -> void:
	assert_eq(_panel._systems.turn_manager.entity_root, _graph)


func test_no_core_presence_on_the_playground_board() -> void:
	for sn in _graph.get_skill_nodes():
		assert_false(sn.core_presence_visible, "%s carries no core dressing" % sn.name)
	_panel._reset_state()
	for sn in _graph.get_skill_nodes():
		assert_false(sn.core_presence_visible, "%s still bare after Reset" % sn.name)
	var gimbals := get_tree().get_nodes_in_group(GimbalWorld.GROUP).filter(
			func(n: Node) -> bool: return _panel.is_ancestor_of(n))
	assert_eq(gimbals.size(), 0, "no GimbalWorld spawned under the panel")


func test_the_tooltip_mount_is_bound_to_the_live_graph() -> void:
	var mount: SandboxTooltipFanMount = _panel.tooltip_mount
	assert_not_null(mount.fan, "the hover tooltip is mounted")
	assert_eq(mount.fan.graph, _panel.graph, "bound to the panel's world graph")
	assert_eq(mount.fan.get_viewport(), _panel.graph.get_viewport(), "inside the world viewport")
