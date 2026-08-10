extends SceneTree

## Cost of one [signal Events.camera_zoom_changed] broadcast at graph scale —
## every live [Edge] connects individually in `_ready()` and each handler
## does a [Line2D] width write. Checks whether that O(N) broadcast is what
## reads as "zoom lag", per the CPU-first triage in
## docs/domain/rendering-performance.md and .claude/rules/graph.md.
##
## Run: [code]godot --headless --path . -s res://test/perf/bench_edge_zoom.gd[/code]
## Must use `-s`, not `--script`, and must not reference autoload globals
## (`Events`, `StatRegistry`, ...) by identifier anywhere in this file — a
## bare SceneTree entry script compiles before autoloads are registered, so a
## static identifier reference fails with "Identifier not found" even inside
## a function never called that early. Reach autoloads via
## `get_root().get_node("Events")` instead.
##
## `next-frame=` is NOT a reliable redraw-cost measurement: `Line2D.width =`
## only marks dirty and queues a redraw, and the headless dummy rasterizer
## elides most of the real draw-pass work. Only `emit=` (signal dispatch +
## setter overhead) is trustworthy here.

var EdgeScene: PackedScene
var SkillNodeScene: PackedScene


func _initialize() -> void:
	await process_frame
	await process_frame
	EdgeScene = load("res://graph/edge.tscn")
	SkillNodeScene = load("res://skill_node/skill_node.tscn")
	print("--- Events.camera_zoom_changed broadcast cost by edge count ---")
	for n in [200, 500, 1000, 2000, 4000]:
		await _bench(n)
	quit()


func _bench(n: int) -> void:
	var root := Node2D.new()
	get_root().add_child(root)

	var nodes: Array = []
	for i in n + 1:
		var sn: Node2D = SkillNodeScene.instantiate()
		sn.position = Vector2(float(i) * 40.0, 0.0)
		root.add_child(sn)
		nodes.append(sn)

	var edges: Array = []
	for i in n:
		var e: Node2D = EdgeScene.instantiate()
		root.add_child(e)
		e.from = nodes[i]
		e.to = nodes[i + 1]
		edges.append(e)

	# Let _ready() run for everything just instanced.
	await process_frame
	await process_frame

	var events := get_root().get_node("Events")
	var t0 := Time.get_ticks_usec()
	events.camera_zoom_changed.emit(1.37)
	var us_emit := Time.get_ticks_usec() - t0

	var t1 := Time.get_ticks_usec()
	await process_frame
	var us_frame := Time.get_ticks_usec() - t1

	print("n=%-5d emit=%9.1f us (%.3f us/edge)  next-frame=%9.1f us" % [
		n, us_emit, float(us_emit) / float(n), us_frame])

	root.queue_free()
	await process_frame
