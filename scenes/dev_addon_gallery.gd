@tool
extends Control

## Dev nicety: grid of SkillNodes, one per addon kind, labeled. Helps eyeball
## addon visuals side-by-side without spinning up a full level.
##
## Add a new addon? Drop its scene into [member addon_scenes] in the editor.
## Each entry instantiates a fresh SkillNode + that addon scene and drops it
## into the grid. Runs in @tool so the editor previews it too.

const ADDON_TILE_SCENE: PackedScene = preload("res://scenes/addon_tile.tscn")

## Addons to display. Order = grid order, left-to-right, top-to-bottom.
@export var addon_scenes: Array[PackedScene] = [
	preload("res://skill_node/addons/defs/clamp_addon.tscn"),
	preload("res://skill_node/addons/defs/spike_ring_addon.tscn"),
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
	for scene in addon_scenes:
		if scene == null:
			continue
		var tile: AddonTile = ADDON_TILE_SCENE.instantiate()
		_grid.add_child(tile)
		tile.configure(scene, tile_size, node_radius)
