extends GutTest

## #910 — the sensor-gated turn-forecast strip beside the initiative bar.
## Forecast order is stubbed by subclassing [TurnManager]; the sensor gate by
## subclassing [VisionSystem] — the strip only ever asks `forecast(n)` and
## `is_visible`/`is_sensed`, so a subclass override is the whole seam.

const _STRIP := preload("res://ui/hud/turn_forecast/turn_forecast_strip.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


class StubTurnManager extends TurnManager:
	var order: Array[Entity] = []

	func forecast(n: int) -> Array[Entity]:
		return order.slice(0, mini(n, order.size()))


class StubVision extends VisionSystem:
	## Nodes no eye on this machine can see or sense.
	var unsensed: Array[SkillNode] = []

	func is_visible(node: SkillNode) -> bool:
		return not unsensed.has(node)

	func is_sensed(node: SkillNode) -> bool:
		return not unsensed.has(node)


var _graph: Graph
var _tm: StubTurnManager
var _vision: StubVision
var _strip: TurnForecastStrip
var _a: Entity
var _b: Entity
var _you: Entity
var _node_of: Dictionary = {}


func _make_entity(ent_name: String, color: Color) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.color = color
	_graph.entities_container.add_child(e)
	var n: SkillNode = _NODE_SCENE.instantiate()
	n.name = ent_name + "Core"
	_graph.add_skill_node(n)
	n.owned_by = e
	_node_of[e] = n
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_tm = autofree(StubTurnManager.new())
	add_child(_tm)
	_vision = autofree(StubVision.new())
	add_child(_vision)
	_a = _make_entity("A", Color.RED)
	_b = _make_entity("B", Color.GREEN)
	_you = _make_entity("You", Color.BLUE)
	_tm.order = [_a, _b, _you, _a]
	_strip = _STRIP.instantiate()
	add_child_autofree(_strip)
	_strip.bind(_tm, _vision, _graph)
	_strip.set_player(_you)
	await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_rest_shows_three_then_hover_expands() -> void:
	assert_eq(_strip.get_slot_entities(), [_a, _b, _you] as Array[Entity], "3 sigils at rest")
	assert_true(_strip.is_slot_highlighted(2), "the seat's own entity is highlighted")
	assert_false(_strip.is_slot_highlighted(0), "others are not")
	assert_eq(_strip.get_caption(), "2 ahead")
	_strip.expanded = true
	await _settle()
	assert_eq(_strip.get_slot_entities(), [_a, _b, _you, _a] as Array[Entity],
			"hover-expand shows the whole (4-long) forecast")
	assert_eq(_strip.get_caption(), "2 ahead", "caption unchanged by expanding")


func test_unsensed_entity_is_omitted_and_caption_hedges() -> void:
	_vision.unsensed = [_node_of[_b]]
	_vision.visibility_changed.emit()
	await _settle()
	assert_eq(_strip.get_slot_entities(), [_a, _you] as Array[Entity], "B is omitted, no '?' slot")
	assert_eq(_strip.get_caption(), "≥ 1 ahead")


func test_rebind_player_rehighlights_and_recaptions() -> void:
	_strip.set_player(_a)
	await _settle()
	assert_eq(_strip.get_slot_entities(), [_a, _b, _you] as Array[Entity], "same order")
	assert_true(_strip.is_slot_highlighted(0))
	assert_false(_strip.is_slot_highlighted(2))
	assert_eq(_strip.get_caption(), "0 ahead")


func test_forecast_changed_rebuilds_once_per_frame() -> void:
	_tm.order = [_you, _a]
	for i in 20:
		_tm.forecast_changed.emit()
	var builds_before: int = _strip.rebuild_count
	await _settle()
	assert_eq(_strip.rebuild_count, builds_before + 1, "20 emits in one frame → one rebuild")
	assert_eq(_strip.get_slot_entities(), [_you, _a] as Array[Entity])


func test_no_process_polling() -> void:
	assert_false(_strip.has_method("_process"), "strip never polls in _process")
	assert_false(_strip.is_processing(), "no _process")
