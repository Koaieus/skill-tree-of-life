class_name LanternLayer
extends Node

const GROUP := &"vision_lantern_layers"

@export var fog_overlay: FogOverlay
@export var vision_system: VisionSystem
@export_range(1, 256) var max_lanterns: int = 64
@export_range(0.0, 5.0, 0.01, "suffix:s") var fade_seconds: float = 0.25
@export_range(16.0, 1024.0, 1.0, "suffix:px") var node_grid_cell: float = 128.0

var uploaded_count: int = 0
var texture: ImageTexture = null


func wake() -> void:
	pass
