extends Node2D
## The [code]mesh2d[/code] stage-gimbal substrate (#1075, shape B): takes one
## slot from the level's lazily created [GimbalBatch] and exposes the
## three-property contract every row of [code]IdleTurnProbe[/code]'s substrate
## table shares ([code]ring_count[/code], [code]tint[/code],
## [code]base_radius[/code]). The probe sets the properties BEFORE add_child
## and `global_position` AFTER it, so the slot is pushed on transform change.
##
## Bench-only env knobs (the bench's arg parser is #1073's, not this unit's):
##   GIMBAL_MESH2D_STYLE = glass (default) | glyph
##   GIMBAL_MESH2D_PAD   = N extra instances placed far off screen, once per
##                         batch — the "full batch, most instances off screen"
##                         culling measurement.
##   GIMBAL_MESH2D_STRIP = <path.png>: the first staged gimbal takes a real
##                         entity tint and saves 5 tight crops of itself,
##                         0.3 s apart, tiled into one horizontal strip.

## Ring radius = the SkillNode radius x this, matching CoreHalos' live halo_scale.
const HALO_SCALE := 1.8

@export_range(1, 5, 1) var ring_count: int = 5:
	set(value):
		ring_count = value
		_push_params()

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_params()

@export var base_radius: float = 32.0:
	set(value):
		base_radius = value
		_push_transform()

var _batch: GimbalBatch
var _slot: int = -1
var _pad_owners: Array = []


func _ready() -> void:
	set_notify_transform(true)
	_batch = GimbalBatch.ensure_for(self)
	_slot = _batch.acquire(self)
	_push_params()
	_push_transform()
	_pad_batch()
	var strip := OS.get_environment("GIMBAL_MESH2D_STRIP")
	if strip != "" and not _batch.has_meta(&"strip_owner"):
		_batch.set_meta(&"strip_owner", true)
		_capture_strip(strip)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_push_transform()
	elif what == NOTIFICATION_EXIT_TREE and _batch != null:
		_batch.release(self)
		for o in _pad_owners:
			_batch.release(o)
		_pad_owners.clear()
		_slot = -1


func _style() -> GimbalBatch.Style:
	return GimbalBatch.Style.SOLID_GLYPH if OS.get_environment("GIMBAL_MESH2D_STYLE") == "glyph" \
			else GimbalBatch.Style.HOLO_GLASS


func _push_params() -> void:
	if _slot == -1:
		return
	_batch.set_slot_params(_slot, tint, ring_count, _style(), randf() * TAU, 1.0)


func _push_transform() -> void:
	if _slot == -1:
		return
	_batch.set_slot_transform(_slot, global_position, base_radius * HALO_SCALE)


func _pad_batch() -> void:
	var pad := int(OS.get_environment("GIMBAL_MESH2D_PAD"))
	if pad <= 0 or _batch.has_meta(&"padded"):
		return
	_batch.set_meta(&"padded", true)
	for i in pad:
		var o := RefCounted.new()
		_pad_owners.append(o)
		var slot := _batch.acquire(o)
		var ang := TAU * float(i) / float(pad)
		var pos := global_position + Vector2.from_angle(ang) * (8000.0 + 4000.0 * float(i % 3))
		_batch.set_slot_params(slot, tint, ring_count, _style(), float(i), 1.0)
		_batch.set_slot_transform(slot, pos, base_radius * HALO_SCALE)
	print("stage    : mesh2d padded with %d off-screen instances (batch live=%d)" % [pad, _batch.live_count()])


## Five frames of this gimbal, 0.3 s apart, cropped to its ring extent and
## upscaled 2x, tiled left-to-right. Tinted with the first owned node's
## entity colour so the look is judged on a real tint, not stage white.
func _capture_strip(path: String) -> void:
	var walk: Node = get_parent()
	while walk != null and not walk is Graph:
		walk = walk.get_parent()
	if walk != null:
		for n: SkillNode in (walk as Graph).get_skill_nodes():
			if n.owned_by != null:
				tint = n.owned_by.color
				break
	await get_tree().create_timer(1.0).timeout
	var frames: Array[Image] = []
	for i in 5:
		await RenderingServer.frame_post_draw
		var xf := get_global_transform_with_canvas()
		var extent := base_radius * HALO_SCALE * (1.0 + float(ring_count - 1) * GimbalBatch.RADIUS_STEP) \
				* xf.get_scale().x * 1.6
		var img := get_viewport().get_texture().get_image()
		# Viewport coords -> window pixels (the stretch mode scales the canvas).
		var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
		extent *= k
		var rect := Rect2i(Vector2i(xf.origin * k - Vector2(extent, extent)), Vector2i(int(extent * 2.0), int(extent * 2.0)))
		var crop := img.get_region(rect)
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
		frames.append(crop)
		await get_tree().create_timer(0.3).timeout
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var strip := Image.create(w * frames.size(), h, false, frames[0].get_format())
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	var err := strip.save_png(path)
	print("strip    : %s%s  tint=%s" % [path, "" if err == OK else " (FAILED: %d)" % err, tint])
