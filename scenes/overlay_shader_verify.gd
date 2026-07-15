extends Node2D

## Pixel-level correctness check for the #177 tiled fog/aura shaders.
##
## Everything else exercised by this issue's warp cycle proves the shader
## COMPILES (xvfb + opengl3) and that two CPU implementations agree with each
## other (test_vision_source_index.gd's lockstep test never runs GLSL). Neither
## proves the shader paints the RIGHT pixels — a texelFetch indexing bug or a
## CPU/GPU grid_origin mismatch would compile clean and render wrong. This
## renders the real FogOverlay/AuraOverlay scenes under opengl3 (a correct,
## if slow, rasterizer — see .claude/rules/godot-workflow.md) and compares
## captured pixels against the same CPU reference math FogOverlay/AuraOverlay
## already trust internally.
##
## [codeblock]
## xvfb-run -a godot --path . --rendering-driver opengl3 --quit-after 30 \
##   res://scenes/overlay_shader_verify.tscn
## [/codeblock]
## Exits 0 on all checks passing, 1 otherwise — grep for FAIL or check the
## exit code in a script.

const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")
const _AURA_SCENE := preload("res://ui/aura_overlay/aura_overlay.tscn")

const _VIEW_SIZE := Vector2(400.0, 400.0)
const _CENTER := Vector2(200.0, 200.0)
const _RADIUS := 100.0
# 8-bit framebuffer round-trip + blend rounding; matches the spike's tolerance.
const _TOL := 0.02

var _fail_count := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	await _verify_fog()
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	await _verify_aura()

	if _fail_count == 0:
		print("VERIFY_RESULT ok=true")
	else:
		print("VERIFY_RESULT ok=false fail_count=%d" % _fail_count)
	get_tree().quit(0 if _fail_count == 0 else 1)


func _verify_fog() -> void:
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.size = _VIEW_SIZE
	add_child(bg)

	var fog: FogOverlay = _FOG_SCENE.instantiate()
	add_child(fog)
	await get_tree().process_frame
	var sources := [{"pos": _CENTER, "radius": _RADIUS, "motion": 0.0}]
	fog.set_sources(sources)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()

	# Centre: fully inside the clear zone -> dark ~ 0 -> screen stays white.
	_check_luma("fog centre (dark≈0, white)", img, _CENTER,
		1.0 - fog._sample_dark(_pixel_center(_CENTER), sources))
	# Well outside the radius -> dark = 1 -> screen goes black.
	var far := _CENTER + Vector2(180.0, 0.0)
	_check_luma("fog far outside (dark=1, black)", img, far,
		1.0 - fog._sample_dark(_pixel_center(far), sources))
	# Mid fade zone.
	var fade_pt := _CENTER + Vector2(90.0, 0.0)
	_check_luma("fog fade zone", img, fade_pt,
		1.0 - fog._sample_dark(_pixel_center(fade_pt), sources))

	fog.queue_free()
	bg.queue_free()

	await _verify_fog_multi_tile()


## The single-circle checks above can't exercise the tile-GATHER itself — with
## one circle there's only ever one tile to visit. This scatters circles far
## enough apart to land in different grid cells (cell size scales with radius,
## so radius=60 circles 220 apart are 3+ cells apart) and samples a union zone
## between two of them, proving the 3x3 neighbourhood read finds the right
## circles from the right tiles, not just the trivial single-tile case.
func _verify_fog_multi_tile() -> void:
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.size = _VIEW_SIZE
	add_child(bg)

	var fog: FogOverlay = _FOG_SCENE.instantiate()
	add_child(fog)
	await get_tree().process_frame
	var a := Vector2(90.0, 200.0)
	var b := Vector2(310.0, 200.0)
	var sources := [
		{"pos": a, "radius": 60.0, "motion": 0.0},
		{"pos": b, "radius": 60.0, "motion": 0.0},
		{"pos": Vector2(200.0, 30.0), "radius": 25.0, "motion": 0.0},
	]
	fog.set_sources(sources)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	# Each circle's own centre must still read clear, proving its OWN tile's
	# bucket was found correctly for each of the three separate tiles.
	_check_luma("multi-tile circle A centre", img, a,
		1.0 - fog._sample_dark(_pixel_center(a), sources))
	_check_luma("multi-tile circle B centre", img, b,
		1.0 - fog._sample_dark(_pixel_center(b), sources))
	# Between A and B, well outside both radii (220 apart, 60+60=120 combined
	# reach) -> must read fully dark, proving distant tiles don't leak in.
	var between := (a + b) * 0.5
	_check_luma("multi-tile between A and B (dark)", img, between,
		1.0 - fog._sample_dark(_pixel_center(between), sources))

	fog.queue_free()
	bg.queue_free()


func _verify_aura() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = _VIEW_SIZE
	# AuraOverlay draws at ZLayers.AURA (-100, see ui/z_layers.gd) — behind the
	# default z=0 band. Without pushing the background further back, the
	# (opaque) background would always win and every sample would read as
	# pure background regardless of what the aura shader actually painted.
	bg.z_as_relative = false
	bg.z_index = -101
	add_child(bg)

	var aura: AuraOverlay = _AURA_SCENE.instantiate()
	add_child(aura)
	await get_tree().process_frame
	var circles := [Vector4(_CENTER.x, _CENTER.y, _RADIUS, 0.0)]
	var colors := [Color.RED]
	aura.set_field(circles, colors)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()

	# Centre: full aura strength -> alpha ~ intensity -> screen reads red-ish.
	var centre_alpha := _aura_reference_alpha(_pixel_center(_CENTER), circles, aura)
	_check_channel("aura centre red channel", img, _CENTER, Color.RED, Color.BLACK, centre_alpha)
	var far := _CENTER + Vector2(180.0, 0.0)
	var far_alpha := _aura_reference_alpha(_pixel_center(far), circles, aura)
	_check_channel("aura far outside (no aura, black)", img, far, Color.RED, Color.BLACK, far_alpha)
	var fade_pt := _CENTER + Vector2(80.0, 0.0)
	var fade_alpha := _aura_reference_alpha(_pixel_center(fade_pt), circles, aura)
	_check_channel("aura fade zone", img, fade_pt, Color.RED, Color.BLACK, fade_alpha)

	aura.queue_free()
	bg.queue_free()


## The fragment shader samples at the PIXEL CENTER (screen pixel N's world
## position is N + 0.5, not N) — standard rasterizer convention, via the
## interpolated `world_pos` varying. `img.get_pixel(x, y)` reads the pixel at
## integer corner (x, y). Comparing the two without this offset drifts by a
## few percent in a steep gradient (measured: fog's default falloff=0.25 fade
## zone, off by ~0.047 in normalized darkness before this fix) even though
## flatter regions (fully clear/fully dark, or aura's wider falloff=0.6 fade)
## happen to agree closely by coincidence. Always feed the CPU reference this
## pixel-center position, not the raw integer sample coordinate.
func _pixel_center(world_pos: Vector2) -> Vector2:
	return Vector2(floor(world_pos.x), floor(world_pos.y)) + Vector2(0.5, 0.5)


## Independent transcription of aura.gdshader's single-entity fold: same
## field_smin union, alpha = (1 - smoothstep(fade_start, 1, min_d)) * tint.a
## * intensity. Deliberately not calling into AuraOverlay's own code.
func _aura_reference_alpha(world_pos: Vector2, circles: Array, aura: AuraOverlay) -> float:
	var k: float = aura.union_smoothness
	var min_d := 1e9
	for c in circles:
		var d: float = world_pos.distance_to(Vector2(c.x, c.y)) / maxf(c.z, 1.0)
		var h: float = clampf(0.5 + 0.5 * (d - min_d) / k, 0.0, 1.0)
		min_d = lerpf(d, min_d, h) - k * h * (1.0 - h)
	if min_d > 1.0:
		return 0.0
	var fade_start: float = 1.0 - maxf(aura.falloff, 1e-4)
	return (1.0 - smoothstep(fade_start, 1.0, min_d)) * aura.intensity


func _check_luma(label: String, img: Image, world_pos: Vector2, expected_luma: float) -> void:
	var px := img.get_pixel(int(world_pos.x), int(world_pos.y))
	var luma := (px.r + px.g + px.b) / 3.0
	var ok := absf(luma - expected_luma) < _TOL
	print("%s VERIFY %s: pixel=%s luma=%.4f expected=%.4f" % [
		"PASS" if ok else "FAIL", label, px, luma, expected_luma])
	if not ok:
		_fail_count += 1


## Screen colour is expected to be lerp(background, foreground, alpha).
func _check_channel(label: String, img: Image, world_pos: Vector2, fg: Color, bg: Color, expected_alpha: float) -> void:
	var px := img.get_pixel(int(world_pos.x), int(world_pos.y))
	var expected := bg.lerp(fg, expected_alpha)
	var ok := absf(px.r - expected.r) < _TOL and absf(px.g - expected.g) < _TOL and absf(px.b - expected.b) < _TOL
	print("%s VERIFY %s: pixel=%s expected≈%s (alpha=%.4f)" % [
		"PASS" if ok else "FAIL", label, px, expected, expected_alpha])
	if not ok:
		_fail_count += 1
