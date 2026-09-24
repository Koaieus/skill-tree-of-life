class_name GimbalWorld
extends Node2D
## Shape A of the gimbal substrate spike (#804): every 3D gimbal rig lives in
## ONE own-world SubViewport, composited ONCE into the graph canvas as a single
## Sprite2D at ZLayers.GIMBAL — over the disks, under fog / spell VFX / HUD.
##
## Contract:
## - 1 3D unit = 1 world px; 2D +y down = 3D -y; the ortho camera looks down
##   -Z from CAMERA_Z, so a rig at 3D (x, -y, 0) sits on world px (x, y).
## - Camera sync is ONE read, two consumers: on `RenderingServer.frame_pre_draw`
##   the root viewport's canvas transform x stretch transform (what is actually
##   drawn, after Camera2D smoothing/limits) feeds both the Camera3D and the
##   composite sprite via [method map_view]. Zero frame lag by construction:
##   `frame_pre_draw` fires after every `_process` and before the draw, and
##   node transforms reach the RenderingServer synchronously.
## - The SubViewport is the root viewport's PIXEL size (window px, not the
##   stretch-logical size), so fill cost is the real thing and texels are 1:1.
## - No glow inside: `project.godot`'s `default_environment` (the game's bloom
##   env) would otherwise apply to this own world too, so the scene pins a
##   plain no-glow Environment. HDR values ride the RGBA16F target
##   (`use_hdr_2d`) into the root viewport's single bloom pass — or don't; that
##   verdict is #804's acceptance 1.
## - Behind-the-disk read, shape A: [method add_rig] parks a depth-only disc
##   at z=0 per rig (writes depth, adds nothing to colour, drawn first among
##   transparents) so the far half of a HOLO_GLASS ring inside the disk radius
##   is culled and the 2D disk shows through the transparent background.
## - Shape A2 ([member split], `gimbal_world_split.tscn`): no occluder. A
##   SECOND SubViewport shares the first's World3D (rigs exist once) and a
##   second Camera3D fed from the same [method map_view] read; the two cameras
##   split the world at the ring plane by near/far ([method clip_planes]).
##   The back half composites just UNDER the node disks, the front half at
##   ZLayers.GIMBAL, so the real 2D disk sits between the halves: hidden
##   exactly where a disk is, visible everywhere else, and opaque rings order
##   correctly because a clip plane does not care about draw order.

const ZLayers := preload("res://ui/z_layers.gd")
const SCENE := "res://skill_node/visuals/gimbal_3d/gimbal_world.tscn"
const SPLIT_SCENE := "res://skill_node/visuals/gimbal_3d/gimbal_world_split.tscn"

## Camera distance above the ring plane, in world px (= 3D units).
const CAMERA_Z := 1000.0
## Nearest clip distance of the front camera, in world px: rings never rise
## above z = +3.4 disk radii, so anything short of CAMERA_Z is safe.
const NEAR := 1.0
const OCCLUDER_SEGMENTS := 48

## Per-rig centre light (owner direction on #804): an OmniLight3D at the
## rig's origin lights the rings' INNER walls (their normals face it) and
## leaves the outer walls to the scene's ambient floor. Range scales with the
## disk radius (the outermost band's inner wall sits at ~3.4 disk radii), so
## the falloff reads the same on every node size. Attenuation is 0 (only the
## range window fades it): in this 1 unit = 1 px world a ring sits 50-150
## units out, where the default inverse-distance decay leaves nothing.
## Specular is kept low so the glass shader's 0.12 roughness does not paint a
## hot streak on the inner face.
const LIGHT_ENERGY := 6.0
const LIGHT_RANGE_SCALE := 4.5
const LIGHT_ATTENUATION := 0.0
const LIGHT_SPECULAR := 0.15

## Depth-only disc: transparent pipeline (so it draws in the same pass as the
## glass rings), lowest priority so it lands first, always writes depth, and
## blend_add of black at alpha 0 leaves colour AND alpha untouched.
const OCCLUDER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_always, cull_disabled, shadows_disabled;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""

static var _occluder_mat: ShaderMaterial

## A2: two cameras split at the ring plane, back composite under the disks.
## Set by `gimbal_world_split.tscn`, which also carries the second viewport.
@export var split := false

@onready var _world: SubViewport = %World
@onready var _camera: Camera3D = %Camera3D
@onready var _rigs: Node3D = %Rigs
@onready var _composite: Sprite2D = %Composite
# Split-only nodes: absent in shape A's scene, so never `%`-bound up front.
@onready var _world_front: SubViewport = get_node_or_null(^"WorldFront")
@onready var _camera_front: Camera3D = get_node_or_null(^"WorldFront/Camera3DFront")
@onready var _composite_front: Sprite2D = get_node_or_null(^"CompositeFront")

var _root: Viewport


## The one GimbalWorld of `host`'s viewport: found by group, else `scene`
## (shape A's by default, [constant SPLIT_SCENE] for A2) instanced as a
## sibling of `host` (same canvas, so the same camera transform applies).
static func acquire(host: Node2D, scene: String = SCENE) -> GimbalWorld:
	var vp := host.get_viewport()
	for w in host.get_tree().get_nodes_in_group(&"gimbal_world"):
		if w is GimbalWorld and w.get_viewport() == vp:
			return w
	var world: GimbalWorld = (load(scene) as PackedScene).instantiate()
	host.get_parent().add_child(world)
	return world


## Pure: the root's world->pixels transform + pixel size -> Camera3D
## `position` / ortho `size` + the composite sprite's world-space rect.
static func map_view(world_to_pixels: Transform2D, pixel_size: Vector2) -> Dictionary:
	var pixels_to_world := world_to_pixels.affine_inverse()
	var scale := world_to_pixels.get_scale()
	var top_left := pixels_to_world * Vector2.ZERO
	var world_size := pixel_size / scale
	var centre := top_left + world_size * 0.5
	return {
		"camera_position": Vector3(centre.x, -centre.y, CAMERA_Z),
		"camera_size": world_size.y,
		"sprite_position": top_left,
		"sprite_scale": Vector2.ONE / scale,
	}


## Pure: (near, far) clip distances of the camera drawing one half of the
## world in split mode. The camera sits at CAMERA_Z looking down -Z, so a
## clip distance d is the plane z = CAMERA_Z - d: the front half (z > 0)
## ends at far = CAMERA_Z, the back half (z < 0) starts at near = CAMERA_Z.
## The halves meet exactly at the ring plane — no gap, no overlap.
static func clip_planes(front: bool) -> Vector2:
	if front:
		return Vector2(NEAR, CAMERA_Z)
	return Vector2(CAMERA_Z, CAMERA_Z * 2.0)


func _ready() -> void:
	add_to_group(&"gimbal_world")
	z_as_relative = false
	if split:
		_setup_split()
	else:
		z_index = ZLayers.GIMBAL
	_root = get_viewport()
	_root.size_changed.connect(_resize)
	_resize()
	RenderingServer.frame_pre_draw.connect(_sync_camera)
	_sync_camera()
	if "--hdr-probe" in OS.get_cmdline_user_args():
		_hdr_probe()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_camera):
		RenderingServer.frame_pre_draw.disconnect(_sync_camera)


## A2 wiring: the front viewport draws the SAME World3D (rigs, light,
## environment exist once); the cameras take the split's near/far; the two
## composites get ABSOLUTE z so the back one lands under the disks whatever
## this node's own z is.
func _setup_split() -> void:
	z_index = ZLayers.GRAPH_DEFAULT
	_world_front.world_3d = _world.find_world_3d()
	var back := clip_planes(false)
	_camera.near = back.x
	_camera.far = back.y
	var front := clip_planes(true)
	_camera_front.near = front.x
	_camera_front.far = front.y
	_composite.z_as_relative = false
	_composite.z_index = ZLayers.GRAPH_DEFAULT - 1
	_composite_front.z_as_relative = false
	_composite_front.z_index = ZLayers.GIMBAL


## Places `rig` at world px `world_pos` with a depth-only disc of `disk_radius`
## under it (shape A only); returns the holder to move/free later.
func add_rig(rig: Gimbal3D, world_pos: Vector2, disk_radius: float) -> Node3D:
	var holder := Node3D.new()
	holder.position = to_world_3d(world_pos)
	holder.add_child(rig)
	if not split:
		var occluder := MeshInstance3D.new()
		occluder.mesh = _disc_mesh(disk_radius)
		occluder.material_override = _occluder_material()
		occluder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(occluder)
	var light := OmniLight3D.new()
	light.omni_range = disk_radius * LIGHT_RANGE_SCALE
	light.light_energy = LIGHT_ENERGY
	light.omni_attenuation = LIGHT_ATTENUATION
	light.light_specular = LIGHT_SPECULAR
	light.shadow_enabled = false
	holder.add_child(light)
	_rigs.add_child(holder)
	return holder


func rig_count() -> int:
	return _rigs.get_child_count()


static func to_world_3d(world_pos: Vector2) -> Vector3:
	return Vector3(world_pos.x, -world_pos.y, 0.0)


func _pixel_size() -> Vector2i:
	# The root Window's `size` is the real pixel size; `get_visible_rect()`
	# is the stretch-logical size under canvas_items stretch.
	if _root is Window:
		return (_root as Window).size
	return _root.get_visible_rect().size


func _resize() -> void:
	var px := _pixel_size()
	if px.x > 0 and px.y > 0:
		_world.size = px
		if split:
			_world_front.size = px


func _sync_camera() -> void:
	if not is_inside_tree():
		return
	var xf := _root.get_final_transform() * _root.get_canvas_transform()
	var m := map_view(xf, Vector2(_pixel_size()))
	_camera.position = m["camera_position"]
	_camera.size = m["camera_size"]
	_composite.position = m["sprite_position"]
	_composite.scale = m["sprite_scale"]
	if split:
		_camera_front.position = m["camera_position"]
		_camera_front.size = m["camera_size"]
		_composite_front.position = m["sprite_position"]
		_composite_front.scale = m["sprite_scale"]


## The HDR-carry probe (#804 acceptance 1): after the rigs have spun for a
## second, print the brightest texel of the sub viewport's texture. > 1.0
## means the RGBA16F target carries emissives above white into the root
## viewport's bloom pass; == 1.0 means the 3D tonemap clamped them.
func _hdr_probe() -> void:
	await get_tree().create_timer(3.0).timeout
	var img := _world.get_texture().get_image()
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
		img.get_format(), img.get_size(), peak, peak_px, above, rig_count()])


static func _occluder_material() -> ShaderMaterial:
	if _occluder_mat == null:
		var sh := Shader.new()
		sh.code = OCCLUDER_SHADER
		_occluder_mat = ShaderMaterial.new()
		_occluder_mat.shader = sh
		_occluder_mat.render_priority = -1
	return _occluder_mat


static func _disc_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in OCCLUDER_SEGMENTS:
		var a0 := TAU * float(i) / OCCLUDER_SEGMENTS
		var a1 := TAU * float(i + 1) / OCCLUDER_SEGMENTS
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(cos(a1), sin(a1), 0.0) * radius)
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(cos(a0), sin(a0), 0.0) * radius)
	return st.commit()
