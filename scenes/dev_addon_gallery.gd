@tool
extends Control

## Dev nicety: grid of SkillNodes, one per addon kind, labeled. Helps eyeball
## addon visuals side-by-side without spinning up a full level.
##
## Add a new addon? Drop its script reference into [member addon_scripts] in
## the editor. Each entry instantiates a fresh SkillNode + that addon and
## drops it into the grid. Runs in @tool so the editor previews it too.

const SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")

## Addons to display. Order = grid order, left-to-right, top-to-bottom.
@export var addon_scripts: Array[Script] = [
	preload("res://skill_node/addons/clamp_addon.gd"),
	preload("res://skill_node/addons/spike_ring_addon.gd"),
]

@export var columns: int = 4:
	set(v):
		columns = v
		if is_node_ready():
			_grid.columns = v
@export var tile_size: Vector2 = Vector2(160.0, 180.0)
@export var node_radius: float = 32.0
@export_tool_button("Rebuild") var _rebuild_button := _rebuild

@onready var _grid: GridContainer = %Grid


func _ready() -> void:
	_grid.columns = columns
	_rebuild()


func _rebuild() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for script in addon_scripts:
		if script == null:
			continue
		_grid.add_child(_make_tile(script))


func _make_tile(addon_script: Script) -> Control:
	var label_h := 24.0
	var tile := PanelContainer.new()
	tile.custom_minimum_size = tile_size

	var vbox := VBoxContainer.new()
	tile.add_child(vbox)

	var visual_host := Control.new()
	visual_host.custom_minimum_size = Vector2(tile_size.x, tile_size.y - label_h)
	visual_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(visual_host)

	var sn: SkillNode = SKILL_NODE_SCENE.instantiate()
	sn.radius = node_radius
	# Visual-only — center the gameplay object inside the Control tile.
	sn.position = visual_host.custom_minimum_size * 0.5
	visual_host.add_child(sn)

	var anchor: Node2D = sn.get_node_or_null("Visuals/AddonAnchor")
	if anchor != null:
		var addon: Node2D = Node2D.new()
		addon.set_script(addon_script)
		anchor.add_child(addon)

	var label := Label.new()
	label.text = _pretty_name(addon_script)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0.0, label_h)
	vbox.add_child(label)

	return tile


func _pretty_name(script: Script) -> String:
	return script.resource_path.get_file().get_basename().capitalize()
