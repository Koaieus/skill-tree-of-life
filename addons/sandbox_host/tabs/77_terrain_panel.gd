@tool
extends PanelContainer

## Live tab panel for terrain (#1796): a hub and three leaves wired into a real
## [Graph], showing the hub's heat spreading to the leaves on a world turn and
## the terrain bars' flash and overflow flicker. The knobs write terrain through
## [method NodeCombat.add_terrain], step [method CombatWorld.flow_temperature],
## pin the bars, and tune their timing and the view's zoom.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

@onready var _node: OptionButton = %Node
@onready var _t: HSlider = %T
@onready var _charge: HSlider = %Charge
@onready var _apply_button: Button = %Apply
@onready var _steps: SpinBox = %Steps
@onready var _step_turn: Button = %StepTurn
@onready var _pin_bars: CheckBox = %PinBars
@onready var _flicker: HSlider = %Flicker
@onready var _flash: HSlider = %Flash
@onready var _zoom: HSlider = %Zoom
@onready var _reset_button: Button = %Reset
@onready var _readout: Label = %Readout
@onready var _stage: Node2D = %Stage
@onready var _world: SubViewport = %World

var _combat: CombatWorld = null
var _graph: Graph = null
var _hub: SkillNode = null
## Hub first, then the three leaves: the OptionButton's item order.
var _nodes: Array[SkillNode] = []


func noop(_obj: Object) -> void:
	pass


func _ready() -> void:
	CombatWorld.reset_live()
	_combat = CombatWorld.live()
	_combat.terrain_settled.connect(_on_terrain_settled)
	_build_world()
	_connect_knobs()
	_world.size_changed.connect(_centre)
	_centre()
	_on_knob()
	await get_tree().process_frame
	_apply_pin()
	_apply()


func _connect_knobs() -> void:
	for slider: HSlider in [_t, _charge, _flicker, _flash, _zoom]:
		slider.value_changed.connect(_on_knob.unbind(1))
	_apply_button.pressed.connect(_apply)
	_step_turn.pressed.connect(_step_world_turn)
	_pin_bars.toggled.connect(_apply_pin.unbind(1))
	_reset_button.pressed.connect(_reset)


func _build_world() -> void:
	_graph = _GRAPH_SCENE.instantiate() as Graph
	_stage.add_child(_graph)
	_hub = _spawn_node(&"Hub", Vector2.ZERO)
	var leaves: Array[SkillNode] = [
		_spawn_node(&"Leaf 1", Vector2(-130, -70)),
		_spawn_node(&"Leaf 2", Vector2(130, -70)),
		_spawn_node(&"Leaf 3", Vector2(0, 120)),
	]
	for leaf in leaves:
		_graph.add_edge(_hub, leaf)


## Name, add to the graph, then place: the graph lays out in its own space.
func _spawn_node(node_name: StringName, pos: Vector2) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = node_name
	_graph.add_skill_node(node)
	node.position = pos
	_nodes.append(node)
	return node


func _centre() -> void:
	_stage.position = Vector2(_world.size) * 0.5


func _on_knob() -> void:
	_stage.scale = Vector2.ONE * _zoom.value
	for node in _nodes:
		node.terrain_bars.flicker_period = _flicker.value
		node.terrain_bars.flash_hold_s = _flash.value


func _apply_pin() -> void:
	for node in _nodes:
		node.pin_health_bar = _pin_bars.button_pressed


func _selected_node() -> SkillNode:
	var index := _node.selected
	return _nodes[index] if index >= 0 and index < _nodes.size() else _hub


func _apply() -> void:
	var node := _selected_node()
	if node == null:
		return
	var c := node.get_combat()
	var fire := ElementRoster.shared().by_id(&"fire")
	var lightning := ElementRoster.shared().by_id(&"lightning")
	c.add_terrain(fire, int(_t.value) - c.terrain_t())
	c.add_terrain(lightning, int(_charge.value) - c.charge())
	_refresh_readout()


func _step_world_turn() -> void:
	CombatWorld.live().flow_temperature(int(_steps.value))
	_refresh_readout()


func _reset() -> void:
	for node in _nodes:
		var c := node.get_combat()
		var fire := ElementRoster.shared().by_id(&"fire")
		var lightning := ElementRoster.shared().by_id(&"lightning")
		c.add_terrain(fire, -c.terrain_t())
		c.add_terrain(lightning, -c.charge())
	_refresh_readout()


func _refresh_readout() -> void:
	var lines := PackedStringArray()
	for node in _nodes:
		var c := node.get_combat()
		lines.append("%s · t %d · charge %d" % [node.name, c.terrain_t(), c.charge()])
	_readout.text = "\n".join(lines)


func _on_terrain_settled(_changed: Array[NodeCombat]) -> void:
	_refresh_readout()


func _exit_tree() -> void:
	if _combat != null:
		if _combat.terrain_settled.is_connected(_on_terrain_settled):
			_combat.terrain_settled.disconnect(_on_terrain_settled)
		_combat = null
	CombatWorld.reset_live()
