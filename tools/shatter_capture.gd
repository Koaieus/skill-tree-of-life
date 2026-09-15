extends Node2D
## Throwaway capture tool for #871: drives AllocationVFX's node-kill "shatter"
## animation deterministically frame-by-frame (via ShatterField.elapsed, never
## wall-clock/_process) and dumps each state to a PNG via the viewport's own
## texture, so the burst can be inspected without relying on a live editor
## redraw (which was proven to collapse the animation to 1-2 captured frames).
##
## Run with (real renderer, windowed, NOT --headless):
##   DISPLAY=:0 godot --path /home/bramh/skill-tree-of-life tools/shatter_capture.tscn

const OUT_DIR := "/tmp/shatter_capture"
const SCRUB_DIR := "/tmp/shatter_capture/scrub"
const ORIGIN := Vector2(256.0, 256.0)
const RADIUS := 24.0
const TINT := Color(0.35, 0.85, 0.4)
const SHARD_COUNT := 14
const KICK_SPEED := 90.0
const CROP_SIZE := 400

# t=0.84 is flight_start(0.6) * window(1.4) - the boom instant; 1.4 is the end
# of the window; 1.45 confirms a clean blank aftermath. 0.46 is the beam
# onset (ray_onset 0.55 * 0.84) and 0.55-0.82 sample the beams growing out of
# the cracks (#871, reopened).
const CAPTURE_TIMES := [
	0.0, 0.3, 0.46, 0.55, 0.62, 0.70, 0.76, 0.82, 0.84, 0.86, 0.90, 0.98, 1.05,
	1.15, 1.30, 1.45,
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(SCRUB_DIR)

	# Fixed, non-moving anchor: the shader hashes its fracture seed from local
	# origin, so nothing under it may move after spawn.
	var anchor := Node2D.new()
	anchor.position = ORIGIN
	add_child(anchor)

	var vfx := AllocationVFX.new()
	anchor.add_child(vfx)
	# _ready() already ran synchronously inside add_child() above (Godot calls
	# NOTIFICATION_READY immediately on entering the tree), including its own
	# `set_process(true)` — undo that now so nothing but us advances the clock.
	vfx.set_process(false)

	vfx._spawn_shatter(anchor.global_position, RADIUS, TINT, 0.0)

	for i in CAPTURE_TIMES.size():
		var t: float = CAPTURE_TIMES[i]
		await _capture(vfx, t, OUT_DIR, "frame_%02d_t%.2f" % [i, t])

	# Bonus: dense scrub of the burst itself.
	var scrub_i := 0
	var t := 0.75
	while t <= 1.0 + 0.0001:
		await _capture(vfx, t, SCRUB_DIR, "scrub_%02d_t%.3f" % [scrub_i, t])
		scrub_i += 1
		t += 0.03

	print("shatter_capture: done")
	get_tree().quit()


func _capture(vfx: AllocationVFX, t: float, dir: String, base_name: String) -> void:
	var field := vfx.get_shard_field()
	field.elapsed = t

	# Force one real render, then read the viewport back. Two distinct awaits:
	# a process frame to let the engine notice the state change, then the
	# render server's own post-draw signal so the frame we read has actually
	# been rasterized (scenes/overlay_shader_verify.gd's proven pattern).
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var half := CROP_SIZE / 2
	var rect := Rect2i(
		int(ORIGIN.x) - half, int(ORIGIN.y) - half, CROP_SIZE, CROP_SIZE)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var cropped := img.get_region(rect)
	cropped.save_png("%s/%s.png" % [dir, base_name])
