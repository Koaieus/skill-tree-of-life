extends Node2D
## The [code]viewport3d[/code] stage-gimbal substrate (#804, A2): one
## [Gimbal3D] rig registered with the level's single [GimbalWorld], adapted
## onto the property contract every row of [code]IdleTurnProbe[/code]'s
## substrate table shares. This Node2D is the rig's 2D anchor: its global
## position is mirrored onto the 3D holder, so moving it moves the rings.
##
## Arms (bench command line): `--gimbal-facets=<N>` absolute facets per ring
## (default: the rig's own), `--gimbal-style=`, `--gimbal-tint=`, `--strip=`,
## `--strip-pan`, `--hdr-probe`. `phase` is set by the probe (0 unless
## `--gimbal-phase=on`) so every rig starts from the same pose.

@export var style: Gimbal3D.Style = Gimbal3D.Style.HOLO_GLASS

@export_range(1, 5, 1) var ring_count: int = 5:
	set(value):
		ring_count = value
		if _rig != null:
			_rig.ring_count = value

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if _rig != null:
			_rig.tint = value

## The SkillNode radius the gimbal sits on, px; passed to the rig 1:1.
@export var base_radius: float = 32.0:
	set(value):
		base_radius = value
		if _rig != null:
			_rig.base_radius = value

## Radians on the rig's spin clock. Forwarded by name: a no-op on a rig that
## predates `phase`.
@export var phase: float = 0.0:
	set(value):
		phase = value
		if _rig != null:
			_rig.set(&"phase", value)

var _rig: Gimbal3D
var _holder: Node3D
var _world: GimbalWorld


func _ready() -> void:
	_world = GimbalWorld.acquire(self)
	_rig = Gimbal3D.new()
	_rig.style = _style_from_cmdline()
	_rig.ring_count = ring_count
	_rig.tint = _tint_from_cmdline()
	_rig.base_radius = base_radius
	_rig.set(&"phase", phase)
	var facets := int(_arg("--gimbal-facets="))
	if facets > 0:
		_rig.facets = facets
	_holder = _world.add_rig(_rig, global_position, base_radius)
	if not _geometry_printed:
		_geometry_printed = true
		# Four quads x two triangles x three vertices per facet per ring.
		print("stage    : viewport3d facets=%d verts/rig=%d" % [
				_rig.facets, _rig.facets * 24 * _rig.ring_count])
	set_notify_transform(true)
	var strip := _arg("--strip=")
	if strip != "" and not _strip_claimed:
		_strip_claimed = true
		_capture_strip.call_deferred(strip, "--strip-pan" in OS.get_cmdline_user_args())
	if "--hdr-probe" in OS.get_cmdline_user_args() and not _hdr_probe_claimed:
		_hdr_probe_claimed = true
		_hdr_probe()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _holder != null:
		_holder.position = GimbalWorld.to_world_3d(global_position)


func _exit_tree() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null


static var _geometry_printed := false
static var _hdr_probe_claimed := false


## The HDR-carry probe (#804 acceptance 1): after the rigs have spun for a
## while, print the brightest texel of the world's back render target. > 1.0
## means the RGBA16F target carries emissives above white into the root
## viewport's bloom pass; == 1.0 means the 3D tonemap clamped them.
func _hdr_probe() -> void:
	await get_tree().create_timer(3.0).timeout
	var img := _world.back_texture().get_image()
	var peak := 0.0
	var peak_px := Color()
	var above := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var m := maxf(c.r, maxf(c.g, c.b))
			if m > 1.0:
				above += 1
			if m > peak:
				peak = m
				peak_px = c
	print("hdr-probe: format=%d size=%s peak=%.3f at %s texels>1.0=%d rigs=%d" % [
			img.get_format(), img.get_size(), peak, peak_px, above, _world.rig_count()])


## `--gimbal-style=<UNIFORM_GLOW|HOLO_GLASS|SOLID_GLYPH>` on the bench command
## line overrides the export (the probe's contract has no style property).
func _style_from_cmdline() -> Gimbal3D.Style:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gimbal-style="):
			var key := arg.get_slice("=", 1).to_upper()
			if Gimbal3D.Style.has(key):
				return Gimbal3D.Style[key]
	return style


## `--gimbal-tint=<rrggbb>` overrides the probe's tint (WHITE for the unowned
## nodes it stages) so the look can be judged in a real entity colour.
func _tint_from_cmdline() -> Color:
	var html := _arg("--gimbal-tint=")
	return Color.html(html) if html != "" and Color.html_is_valid(html) else tint


static func _arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.get_slice("=", 1)
	return ""


## — look strip (#1074 owner follow-up) ————————————————————————————————————————
## `--strip=<png>`: the first staged adapter (nearest the view centre) grabs
## STRIP_FRAMES crops of itself STRIP_GAP apart and tiles them horizontally.
## `--strip-pan` additionally drives a brisk pan + zoom across the capture, the
## crop tracking the gimbal's screen position, so rings swimming off their disk
## show as ring-vs-disk offset inside the crop. Needs `--seconds` >= 3.
static var _strip_claimed := false
const STRIP_FRAMES := 5
const STRIP_GAP := 0.3
const STRIP_CROP := 300
const STRIP_SCALE := 2


func _capture_strip(path: String, pan: bool) -> void:
	await get_tree().create_timer(0.4).timeout
	var vp := get_viewport()
	if pan:
		var cam := vp.get_camera_2d()
		cam.pan_to(cam.global_position)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(cam, ^"global_position", cam.global_position + Vector2(320, -140), 1.4)
		tw.tween_property(cam, ^"zoom", cam.zoom * 1.3, 1.4)
	var side := STRIP_CROP * STRIP_SCALE
	var strip := Image.create(side * STRIP_FRAMES, side, false, Image.FORMAT_RGBA8)
	for i in STRIP_FRAMES:
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		# Canvas coords -> texel coords by the image/visible-rect ratio (the
		# window may be letterboxed, so the final transform alone misplaces).
		var canvas_px: Vector2 = get_global_transform_with_canvas() * Vector2.ZERO
		var px := canvas_px * (Vector2(img.get_size()) / vp.get_visible_rect().size)
		var crop := img.get_region(Rect2i(Vector2i(px) - Vector2i(STRIP_CROP / 2, STRIP_CROP / 2),
				Vector2i(STRIP_CROP, STRIP_CROP)))
		crop.resize(side, side, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(crop, Rect2i(0, 0, side, side), Vector2i(side * i, 0))
		await get_tree().create_timer(STRIP_GAP).timeout
	print("strip: %s (%d frames, %.1fs apart, %s)" % [path, STRIP_FRAMES, STRIP_GAP,
			"pan+zoom" if pan else "static"], " err=", strip.save_png(path))
