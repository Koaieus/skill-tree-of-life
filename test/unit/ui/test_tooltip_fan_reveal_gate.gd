extends GutTest

## #1036 — the hover leak. `input_pickable` widens to sensed-only nodes while a
## scout shot is armed, and a pickable node emits `Events.skill_node_hovered`.
## The tooltip fan gates on [member SkillNode.revealed]: a sensed-only node
## shows nothing (info_gating's "archetype only" law), a revealed one opens a fan.

const _TOOLTIP_FAN_SCENE := preload("res://ui/tooltip_fan/tooltip_fan.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _fan: TooltipFan
var _node: SkillNode


func before_each() -> void:
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(_node)
	_fan = _TOOLTIP_FAN_SCENE.instantiate() as TooltipFan
	add_child_autofree(_fan)
	await get_tree().process_frame


func after_each() -> void:
	Events.skill_node_unhovered.emit()


func test_a_revealed_node_opens_a_fan() -> void:
	_node.revealed = true
	Events.skill_node_hovered.emit(_node)
	assert_not_null(_fan._current_fan, "a revealed node hover opens a fan")
	assert_true(_fan.visible)


func test_an_unrevealed_node_opens_no_fan() -> void:
	_node.revealed = false
	Events.skill_node_hovered.emit(_node)
	assert_null(_fan._current_fan, "a sensed-only (unrevealed) node shows nothing on hover")
	assert_false(_fan.visible)
