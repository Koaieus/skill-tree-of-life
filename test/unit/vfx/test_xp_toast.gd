extends GutTest

## XP gain must be visible: a toast on the gaining entity's core, and on the
## Hero Sigil Card instead when that entity is the bound player.
##
## The chain under test is `xp.replenish` → [signal PoolStat.replenished_by] →
## `Events.entity_xp_gained` → [FloaterDirector]. It exists because
## `PoolStat.replenished` is zero-arg and only fires when the pool *fills*, so
## neither it nor `current_changed` can answer "how much did you just gain" —
## which is the only number worth showing.

const _DIRECTOR_SCENE := preload("res://ui/floating_number_layer/floater_director.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _director: FloaterDirector
var _renderer: FloaterToasterManager
var _graph: Graph
var _entity: Entity
var _core: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_core = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_core)

	_director = _DIRECTOR_SCENE.instantiate() as FloaterDirector
	_director.vision_system = null  # no fog gating in tests
	add_child_autofree(_director)
	_renderer = _director.renderer

	_entity = autofree(Entity.new())
	_entity.display_name = "XPer"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame  # _ready wires the xp relay
	_entity.core_location = _core


func _toasters() -> Array:
	return _renderer.get_children().filter(func(c): return c is FloaterToaster)


func _first_toast_text() -> String:
	var toasters := _toasters()
	if toasters.is_empty():
		return ""
	var vbox := (toasters[0] as FloaterToaster).get_node("VBoxContainer") as VBoxContainer
	if vbox.get_child_count() == 0:
		return ""
	return (vbox.get_child(0) as FloaterToast).label.text


func test_pool_replenish_carries_the_amount_asked_for() -> void:
	var seen: Array[float] = []
	_entity.stat_board.xp.replenished_by.connect(func(a: float) -> void: seen.append(a))
	_entity.stat_board.xp.replenish(3.0)
	assert_eq(seen, [3.0] as Array[float], "the grant, not the delta that fit under the cap")


func test_overflowing_grant_still_reports_the_full_grant() -> void:
	# xp cap is 5 by default: a 40 XP kill reward must read "+40 XP", not "+5".
	# The excess is carried into the next level by GrowablePoolStatDef, so the
	# grant is the honest number.
	var seen: Array[float] = []
	_entity.stat_board.xp.replenished_by.connect(func(a: float) -> void: seen.append(a))
	_entity.stat_board.xp.replenish(40.0)
	assert_eq(seen, [40.0] as Array[float], "clamping at the cap doesn't shrink the announcement")


func test_xp_gain_is_relayed_to_the_bus_keyed_by_entity() -> void:
	var seen: Array = []
	var handler := func(e: Entity, a: float) -> void: seen.append([e, a])
	Events.entity_xp_gained.connect(handler)
	_entity.stat_board.xp.replenish(4.0)
	Events.entity_xp_gained.disconnect(handler)
	assert_eq(seen.size(), 1, "one bus emission per grant")
	assert_eq(seen[0][0], _entity, "keyed by the gaining entity")
	assert_eq(seen[0][1], 4.0, "carrying the amount")


func test_xp_gain_toasts_on_the_core() -> void:
	_entity.stat_board.xp.replenish(4.0)
	await get_tree().process_frame
	assert_eq(_toasters().size(), 1, "one toaster, anchored on the core")
	assert_eq(_first_toast_text(), "+4 XP", "the XP grant is announced")


func test_player_xp_toasts_on_the_hero_sigil_anchor_instead() -> void:
	# #91's routing: the bound player's entity-level toasts belong on the HUD
	# card, not out on the map.
	var hud_anchor := Node2D.new()
	add_child_autofree(hud_anchor)
	hud_anchor.global_position = Vector2(640, 360)
	_director.player = _entity
	_director.player_anchor = hud_anchor

	_entity.stat_board.xp.replenish(4.0)
	await get_tree().process_frame
	var toasters := _toasters()
	assert_eq(toasters.size(), 1, "one toaster")
	assert_eq((toasters[0] as FloaterToaster).global_position, Vector2(640, 360),
			"routed to the hero sigil anchor, not the core")


func test_zero_grant_is_silent() -> void:
	_entity.stat_board.xp.replenish(0.0)
	await get_tree().process_frame
	assert_eq(_toasters().size(), 0, "a no-op grant announces nothing")
