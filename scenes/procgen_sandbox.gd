extends GameRoot

## Drop-in tester: picks a preset, runs [GraphProcgen] into the child [Graph],
## then frames the result with the camera. No entities, no turn loop — this
## is just to see the generator output.

@export var preset: GraphProcgenConfig
@onready var camera: GraphCamera = %GraphCamera



func _ready() -> void:
	if preset == null or graph == null:
		push_warning("ProcgenSandbox: assign `preset` and `graph` in the inspector")
		return
	var result := GraphProcgen.generate(preset, graph)
	var node_count: int = (result.get("nodes") as Array).size()
	print("[procgen] generated %d nodes" % node_count)
	_frame_camera()
	#super()

func _frame_camera() -> void:
	if camera == null or preset == null or preset.shape_mask == null:
		return
	var bounds := preset.shape_mask.aabb()
	camera.position = bounds.position + bounds.size * 0.5
	# Coarse fit: zoom out so the AABB fits in the viewport.
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0 and bounds.size.x > 0.0 and bounds.size.y > 0.0:
		var z := minf(vp.x / bounds.size.x, vp.y / bounds.size.y) * 0.9
		camera.zoom = Vector2(z, z)
