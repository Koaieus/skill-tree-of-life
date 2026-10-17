extends GutTest

## [member TooltipFan.held]: while a menu holds the fan down, a hover raises
## nothing, and taking the hold drops a fan already up.

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


func test_a_held_fan_ignores_a_hover() -> void:
	_fan.held = true
	Events.skill_node_hovered.emit(_node)
	assert_null(_fan._current_fan, "a held fan raises nothing on hover")
	assert_false(_fan.visible)


func test_holding_drops_a_raised_fan_and_releasing_lets_hovers_through() -> void:
	Events.skill_node_hovered.emit(_node)
	assert_not_null(_fan._current_fan, "control: an unheld hover raises the fan")
	_fan.held = true
	assert_null(_fan._current_fan, "taking the hold drops it")
	assert_false(_fan.visible)
	_fan.held = false
	Events.skill_node_hovered.emit(_node)
	assert_not_null(_fan._current_fan, "released, hovers raise it again")
