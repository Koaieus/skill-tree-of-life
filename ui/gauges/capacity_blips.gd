@tool
class_name CapacityBlips
extends GridContainer
## N-of-max pip display — resolves #87 slice 2 ("empty mana crystal"
## blips). Used for blade-size pips and the Magic spell bar's degree
## icon. Instances CapacityPip children (leaf-level programmatic
## composition per scene-composition.md — the count is data-driven, not
## a fixed structural tree, so this is the sanctioned case-by-case use of
## code composition rather than a hand-authored fixed scene).

const PIP_SCENE := preload("res://ui/gauges/capacity_pip.tscn")

@export var max_count: int = 3:
	set(v):
		var nv: int = max(0, v)
		if max_count == nv:
			return
		max_count = nv
		_rebuild()

@export var count: int = 0:
	set(v):
		count = clamp(v, 0, max_count)
		_apply_state()

@export var fill_color: Color = Color(0.62, 0.21, 0.21, 1.0):
	set(v):
		fill_color = v
		_apply_state()

@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		empty_color = v
		_apply_state()

@export var pip_size: Vector2 = Vector2(13, 13):
	set(v):
		pip_size = v
		for pip in get_children():
			pip.custom_minimum_size = pip_size

## Indices (0-based) currently selection-highlighted, e.g. blade nodes
## picked in the Melee builder. Cleared/rebuilt on every count() change.
var highlighted_indices: Array[int] = []:
	set(v):
		highlighted_indices = v
		_apply_state()

## Per-filled-pip color override (#406) — index i colors the i'th filled pip
## (0..count-1); shorter than `count` falls back to `fill_color` for the
## remainder. Empty (the default) keeps the single-color behavior. Lets one
## blip row mix budget "kinds" sharing the same pool (e.g. blade-member
## spend vs. a temp Spike vs. a temp Clamp) while still reading as one
## N-of-max gauge.
var segment_colors: Array[Color] = []:
	set(v):
		segment_colors = v
		_apply_state()

## Melee blade blips (#406 follow-up): pips as click/hover UI elements instead
## of a pure readout. Off by default — every other CapacityBlips consumer
## (CombatCardMelee's size gauge, the Magic spell-bar degree icon) stays a
## non-interactive `MOUSE_FILTER_IGNORE` readout.
@export var interactive: bool = false:
	set(v):
		interactive = v
		_rebuild()

## Parallel to segment_colors — the SkillNode index i's pip represents, or
## null for a pip with no real node behind it (unspent blade capacity). Only
## consulted when `interactive`.
var bound_nodes: Array = []:
	set(v):
		bound_nodes = v
		_apply_state()

## Addon-outline colors per filled pip, parallel to segment_colors. A default
## (fully transparent) Color at index i means "no outline of that kind" —
## see capacity_pip.gdshader.
var outline_colors_a: Array[Color] = []:
	set(v):
		outline_colors_a = v
		_apply_state()

var outline_colors_b: Array[Color] = []:
	set(v):
		outline_colors_b = v
		_apply_state()

## True at index i marks a player-applied (temp) upgrade on that pip's node,
## as opposed to one that shipped from procgen — see CapacityPip.manual_marker.
var manual_markers: Array[bool] = []:
	set(v):
		manual_markers = v
		_apply_state()

## Emitted on a left-click of an interactive pip with a bound node.
signal pip_clicked(node: SkillNode)
## Emitted when the mouse enters/exits an interactive pip with a bound node.
signal pip_hover_changed(node: SkillNode, hovering: bool)

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	# Immediate free (not queue_free): the same names get reused below in the
	# same call, and a deferred free leaves the old node parented (still
	# holding its name slot) until frame end, which previously produced
	# "Children name does not match parent name in hashtable" errors when
	# max_count changed more than once before the deferred frees flushed.
	for child in get_children():
		remove_child(child)
		child.free()
	for i in max_count:
		var pip: CapacityPip = PIP_SCENE.instantiate()
		pip.name = "CapacityPip_%02d" % i
		pip.custom_minimum_size = pip_size
		add_child(pip)
		if interactive:
			pip.mouse_filter = Control.MOUSE_FILTER_STOP
			pip.gui_input.connect(_on_pip_gui_input.bind(i))
			pip.mouse_entered.connect(_on_pip_hover.bind(i, true))
			pip.mouse_exited.connect(_on_pip_hover.bind(i, false))
		else:
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Deliberately NOT stamping pip.owner in the editor: doing so let the
		# editor bake these script-created pips into any consuming scene as
		# persistent "editable children" overrides, which then collided with
		# this same _rebuild() teardown on the next load (mismatched pip
		# count/identity vs. what the script expects). Pips render fine in
		# the editor viewport without an owner — they're just not individually
		# selectable in the Scene dock, which is correct for a script-owned,
		# count-driven leaf composition (see class doc above).
	_apply_state()

func _apply_state() -> void:
	var children := get_children()
	for i in children.size():
		var pip: CapacityPip = children[i]
		pip.fill_color = segment_colors[i] if i < segment_colors.size() else fill_color
		pip.empty_color = empty_color
		pip.filled = i < count
		pip.highlighted = i in highlighted_indices
		pip.outline_color_a = outline_colors_a[i] if i < outline_colors_a.size() else Color(0, 0, 0, 0)
		pip.outline_color_b = outline_colors_b[i] if i < outline_colors_b.size() else Color(0, 0, 0, 0)
		pip.manual_marker = manual_markers[i] if i < manual_markers.size() else false


## `bound_nodes[index]` read defensively — per gdscript-pitfalls.md, a typed
## read of a freed Object crashes at the assignment, so this stays untyped
## until the validity check.
func _bound_node_at(index: int) -> SkillNode:
	if index < 0 or index >= bound_nodes.size():
		return null
	var stored = bound_nodes[index]
	return stored if is_instance_valid(stored) else null


func _on_pip_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var node := _bound_node_at(index)
	if node != null:
		pip_clicked.emit(node)


func _on_pip_hover(index: int, hovering: bool) -> void:
	var node := _bound_node_at(index)
	if node != null:
		pip_hover_changed.emit(node, hovering)
