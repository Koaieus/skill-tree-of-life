extends Node2D

## GPU cost harness for [FogOverlay] / [AuraOverlay]. See #133.
##
## [b]This is the only way to answer the question #133 actually asks.[/b] Both
## overlays draw one screen-covering rect whose fragment shader loops over every
## circle, so their cost is O(pixels × circles) per frame. That cost is
## invisible to the test suite (dummy renderer never runs a fragment shader) and
## meaningless under `xvfb` + opengl3 (llvmpipe is a software rasterizer; it
## cannot parallelize the loop the way real hardware does, so it overstates the
## cost by an unknown factor).
##
## [b]So: run this on real hardware, with the real driver.[/b]
## [codeblock]
## godot --path . scenes/overlay_perf_harness.tscn
## [/codeblock]
## Under xvfb it is good for exactly one thing — proving the shaders compile and
## the scene runs. [b]Do not read its timings there.[/b]
##
## The number that decides #133 is the [i]delta[/i]: overlay-on minus overlay-off
## GPU milliseconds, at circle counts spanning today (~15) to the planned late
## game (~400+). If that delta stays small as circles grow, the per-pixel loop
## was never the ceiling and #133's GPU half closes as "the 256-cap was the
## actual bug". If it grows linearly in circle count, the loop is real.
##
## Drives [method FogOverlay.set_sources] / [method AuraOverlay.set_field] — the
## same entry points the game uses — so it keeps measuring the right thing
## across any change to how those overlays render.
##
## Note this isolates the [i]GPU[/i]: with no VisionSystem wired, FogOverlay's
## per-element dimming pass short-circuits. The CPU half of #133 was measured
## separately and fixed (VisionSourceIndex).

## Circle counts to sweep. 15 ≈ today; 400–512 ≈ four entities at ~100 owned
## nodes (#133's scale); 1000–4000 ≈ #177's target — 1000-2000 node graphs,
## up to 20 entities × 200 owned nodes for AuraOverlay's worst case.
@export var circle_counts: Array[int] = [0, 15, 100, 250, 512, 1000, 2000, 4000]
## Frames discarded per configuration before sampling — lets the driver settle
## and the shader variant compile.
@export var warmup_frames: int = 20
## Frames averaged per configuration.
@export var sample_frames: int = 60
## Circles are scattered over the visible rect so they actually cover pixels;
## a circle off-screen costs its loop iteration but shades nothing.
@export var circle_radius: float = 120.0
@export var entity_count: int = 4

@export var fog: FogOverlay
@export var aura: AuraOverlay

const _ENTITY_COLORS: Array[Color] = [
	Color(0.4, 0.8, 1.0), Color(0.95, 0.4, 0.4),
	Color(1.0, 0.6, 0.2), Color(0.5, 0.9, 0.5),
]

var _viewport_rid: RID


func _ready() -> void:
	_apply_cmdline_overrides()
	# vsync would clamp the frame rate and hide everything we came to measure.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)

	# Neither overlay has its real dependency (VisionSystem / Graph) wired, so
	# neither will refresh itself out from under us. Visibility is the switch.
	fog.visible = false
	aura.visible = false

	await _run()
	get_tree().quit()


func _run() -> void:
	var view := _visible_world_rect()
	print("\n=== #133 overlay GPU cost ===")
	print("adapter : %s" % RenderingServer.get_video_adapter_name())
	print("driver  : %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("viewport: %dx%d   (%s)" % [
		get_viewport().size.x, get_viewport().size.y,
		"SOFTWARE RASTERIZER — timings are meaningless" if _is_software() else "real GPU",
	])
	print("averaging %d frames per configuration, %d warmup\n" % [sample_frames, warmup_frames])

	fog.visible = false
	aura.visible = false
	var baseline := await _measure()
	print("baseline (both overlays hidden): %.3f ms GPU\n" % baseline)

	print("circles |   fog ms |  aura ms |  both ms | fog delta | aura delta")
	print("--------|----------|----------|----------|-----------|-----------")
	for n in circle_counts:
		fog.set_sources(_fog_sources(n, view))
		aura.set_field(_aura_circles(n, view), _ENTITY_COLORS.slice(0, entity_count))

		fog.visible = true
		aura.visible = false
		var fog_ms := await _measure()

		fog.visible = false
		aura.visible = true
		var aura_ms := await _measure()

		fog.visible = true
		var both_ms := await _measure()

		print("%7d | %8.3f | %8.3f | %8.3f | %9.3f | %10.3f" % [
			n, fog_ms, aura_ms, both_ms, fog_ms - baseline, aura_ms - baseline])

	print("\nRead the DELTA columns, not the absolutes. Linear growth in circle")
	print("count => the per-pixel loop is the ceiling, and #133 needs the fix.")
	print("Flat => the loop is not the ceiling; close #133's GPU half.\n")


## Average GPU milliseconds over `sample_frames`, after discarding `warmup_frames`.
func _measure() -> float:
	for i in warmup_frames:
		await RenderingServer.frame_post_draw
	var total := 0.0
	for i in sample_frames:
		await RenderingServer.frame_post_draw
		total += RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
	return total / float(sample_frames)


## The world-space rect the camera actually shows. Circles outside it still cost
## a loop iteration but shade no pixels, which would understate the fill cost.
func _visible_world_rect() -> Rect2:
	var size := Vector2(get_viewport().size)
	return Rect2(-size * 0.5, size)


func _fog_sources(n: int, view: Rect2) -> Array:
	seed(0x133)
	var out: Array = []
	for i in n:
		out.append({
			"pos": Vector2(randf_range(view.position.x, view.end.x),
				randf_range(view.position.y, view.end.y)),
			"radius": circle_radius,
			"motion": 0.0,
		})
	return out


func _aura_circles(n: int, view: Rect2) -> Array:
	seed(0x133)
	var out: Array = []
	for i in n:
		out.append(Vector4(
			randf_range(view.position.x, view.end.x),
			randf_range(view.position.y, view.end.y),
			circle_radius,
			float(i % entity_count)))
	return out


## `godot --path . scenes/overlay_perf_harness.tscn -- --counts=0,15 --frames=5 --warmup=2`
## Mostly so the xvfb smoke test can ask for a tiny sweep — a 512-circle frame
## on llvmpipe takes seconds.
func _apply_cmdline_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"counts":
				var parsed: Array[int] = []
				for tok in parts[1].split(",", false):
					parsed.append(int(tok))
				if not parsed.is_empty():
					circle_counts = parsed
			"frames":
				sample_frames = maxi(1, int(parts[1]))
			"warmup":
				warmup_frames = maxi(0, int(parts[1]))


func _is_software() -> bool:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	return adapter.contains("llvmpipe") or adapter.contains("softpipe") or adapter.contains("swiftshader")
