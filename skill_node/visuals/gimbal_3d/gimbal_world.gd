class_name GimbalWorld
extends Node2D
## THE gimbal substrate (#804, shape A2): every 3D gimbal rig lives in ONE
## World3D drawn by two SubViewports, each composited once into the graph
## canvas — the back half just UNDER the node disks, the front half at
## ZLayers.GIMBAL (over disks, under fog / spell VFX / HUD). The real 2D disk
## sits between the halves: hidden exactly where a disk is, visible everywhere
## else, and opaque rings order correctly because a clip plane does not care
## about draw order.
##
## Contract:
## - 1 3D unit = 1 world px; 2D +y down = 3D -y; both ortho cameras look down
##   -Z from CAMERA_Z, so a rig at 3D (x, -y, 0) sits on world px (x, y).
## - `WorldBack` owns the World3D (rigs, light, environment exist once);
##   `WorldFront` shares it. The cameras split the world at the ring plane by
##   near/far ([method clip_planes]).
## - Camera sync is ONE read, four consumers: on `RenderingServer.frame_pre_draw`
##   the root viewport's canvas transform x stretch transform (what is actually
##   drawn, after Camera2D smoothing/limits) feeds both cameras and both
##   composites via [method map_view]. Zero frame lag by construction:
##   `frame_pre_draw` fires after every `_process` and before the draw, and
##   node transforms reach the RenderingServer synchronously.
## - Both SubViewports are the root viewport's PIXEL size (window px, not the
##   stretch-logical size), so fill cost is the real thing and texels are 1:1;
##   both are 4x MSAA.
## - No glow inside: `project.godot`'s `default_environment` (the game's bloom
##   env) would otherwise apply to this own world too, so the scene pins a
##   plain no-glow Environment. HDR values ride the RGBA16F targets
##   (`use_hdr_2d`) into the root viewport's single bloom pass.
## - Idle: both render targets are DISABLED while no rig is on screen
##   ([method visible_rig_count]). Each holder carries a
##   VisibleOnScreenNotifier3D; but a sleeping viewport culls nothing, so its
##   notifiers can never report "entered" — while asleep, [method _sync_camera]
##   wakes the world on a cheap sphere-vs-view test and the notifiers take over.
## - One world per viewport: authored beside the Graph in `game_root.tscn` and
##   found by group ([method acquire]).

const ZLayers := preload("res://ui/z_layers.gd")
const SCENE := "res://skill_node/visuals/gimbal_3d/gimbal_world.tscn"
const GROUP := &"gimbal_world"

## Camera distance above the ring plane, in world px (= 3D units).
const CAMERA_Z := 1000.0
## Nearest clip distance of the front camera, in world px: rings never rise
## above z = +3.4 disk radii, so anything short of CAMERA_Z is safe.
const NEAR := 1.0

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

@onready var _world_back: SubViewport = %WorldBack
@onready var _world_front: SubViewport = %WorldFront
@onready var _camera_back: Camera3D = %Camera3DBack
@onready var _camera_front: Camera3D = %Camera3DFront
@onready var _rigs: Node3D = %Rigs
@onready var _composite_back: Sprite2D = %CompositeBack
@onready var _composite_front: Sprite2D = %CompositeFront

var _root: Viewport
## notifier -> on screen, per live holder. The count of `true`s gates rendering.
var _on_screen: Dictionary = {}
var _awake := false


## The one GimbalWorld of `host`'s viewport: found by group; else [constant SCENE]
## instanced under the nearest Graph ancestor of `host` (the board's canvas,
## never inside a SkillNode's ShaderStack); else, with no Graph at all (bare
## fixtures), as a sibling of `host`.
static func acquire(host: Node2D) -> GimbalWorld:
	var vp := host.get_viewport()
	for w in host.get_tree().get_nodes_in_group(GROUP):
		if w is GimbalWorld and w.get_viewport() == vp:
			return w
	var world: GimbalWorld = (load(SCENE) as PackedScene).instantiate()
	var parent := host.get_parent()
	var n := parent
	while n != null:
		if n is Graph:
			parent = n
			break
		n = n.get_parent()
	parent.add_child(world)
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


func _enter_tree() -> void:
	# In the group before ANY `_ready` of the scene runs: `acquire` from a
	# SkillNode's `_ready` (the Graph is an earlier sibling) must find it.
	add_to_group(GROUP)


func _ready() -> void:
	z_as_relative = false
	_world_front.world_3d = _world_back.find_world_3d()
	var back := clip_planes(false)
	_camera_back.near = back.x
	_camera_back.far = back.y
	var front := clip_planes(true)
	_camera_front.near = front.x
	_camera_front.far = front.y
	_composite_back.z_as_relative = false
	_composite_back.z_index = ZLayers.GRAPH_DEFAULT - 1
	_composite_front.z_as_relative = false
	_composite_front.z_index = ZLayers.GIMBAL
	_set_awake(false)
	_root = get_viewport()
	_root.size_changed.connect(_resize)
	_resize()
	RenderingServer.frame_pre_draw.connect(_sync_camera)
	_sync_camera()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_camera):
		RenderingServer.frame_pre_draw.disconnect(_sync_camera)


## Places `rig` at world px `world_pos` over a disk of `disk_radius` (the
## centre light's range scales with it); returns the holder to move/free later.
func add_rig(rig: Gimbal3D, world_pos: Vector2, disk_radius: float) -> Node3D:
	var holder := Node3D.new()
	holder.position = to_world_3d(world_pos)
	holder.add_child(rig)
	var light := OmniLight3D.new()
	light.omni_range = disk_radius * LIGHT_RANGE_SCALE
	light.light_energy = LIGHT_ENERGY
	light.omni_attenuation = LIGHT_ATTENUATION
	light.light_specular = LIGHT_SPECULAR
	light.shadow_enabled = false
	holder.add_child(light)
	# In the tree first: the rig builds its rings (and their radii) in `_ready`.
	_rigs.add_child(holder)
	var r := _outer_radius(rig, disk_radius * LIGHT_RANGE_SCALE)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = &"OnScreen"
	notifier.aabb = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	holder.add_child(notifier)
	_on_screen[notifier] = false
	notifier.screen_entered.connect(_on_notifier.bind(notifier, true))
	notifier.screen_exited.connect(_on_notifier.bind(notifier, false))
	holder.tree_exiting.connect(_forget.bind(notifier))
	_recount()
	return holder


func rig_count() -> int:
	return _rigs.get_child_count()


## Holders whose notifier currently reports on screen.
func visible_rig_count() -> int:
	return _on_screen.values().count(true)


## The back half's render target (the `--hdr-probe` reads it).
func back_texture() -> ViewportTexture:
	return _world_back.get_texture()


static func to_world_3d(world_pos: Vector2) -> Vector3:
	return Vector3(world_pos.x, -world_pos.y, 0.0)


## The rig's rotation sphere: its outermost ring's radius (`outer_radius` meta
## on each ring mesh), or `fallback` before it has built any.
static func _outer_radius(rig: Gimbal3D, fallback: float) -> float:
	var r := 0.0
	for c in rig.get_children():
		if c.has_meta(&"outer_radius"):
			r = maxf(r, float(c.get_meta(&"outer_radius")))
	return r if r > 0.0 else fallback


func _on_notifier(notifier: VisibleOnScreenNotifier3D, on: bool) -> void:
	if _on_screen.has(notifier):
		_on_screen[notifier] = on
		_recount()


func _forget(notifier: VisibleOnScreenNotifier3D) -> void:
	_on_screen.erase(notifier)
	_recount()


func _recount() -> void:
	_set_awake(visible_rig_count() > 0)


func _set_awake(awake: bool) -> void:
	_awake = awake
	var mode := SubViewport.UPDATE_ALWAYS if awake else SubViewport.UPDATE_DISABLED
	_world_back.render_target_update_mode = mode
	_world_front.render_target_update_mode = mode
	# A disabled target keeps its last frame; hide it so a stale ring never
	# ghosts at the view's edge while the composites follow the camera.
	_composite_back.visible = awake
	_composite_front.visible = awake


func _pixel_size() -> Vector2i:
	# The root Window's `size` is the real pixel size; `get_visible_rect()`
	# is the stretch-logical size under canvas_items stretch.
	if _root is Window:
		return (_root as Window).size
	return _root.get_visible_rect().size


func _resize() -> void:
	var px := _pixel_size()
	if px.x > 0 and px.y > 0:
		_world_back.size = px
		_world_front.size = px


func _sync_camera() -> void:
	if not is_inside_tree():
		return
	var xf := _root.get_final_transform() * _root.get_canvas_transform()
	var px := Vector2(_pixel_size())
	var m := map_view(xf, px)
	for cam: Camera3D in [_camera_back, _camera_front]:
		cam.position = m["camera_position"]
		cam.size = m["camera_size"]
	for sprite: Sprite2D in [_composite_back, _composite_front]:
		sprite.position = m["sprite_position"]
		sprite.scale = m["sprite_scale"]
	if not _awake and not _on_screen.is_empty():
		_wake_if_in_view(Rect2(m["sprite_position"], px * Vector2(m["sprite_scale"])))


## Asleep, the notifiers are blind (nothing is culled); wake on the first
## holder whose rotation sphere touches the view, and let them take over.
func _wake_if_in_view(view: Rect2) -> void:
	for notifier: VisibleOnScreenNotifier3D in _on_screen:
		var p := notifier.global_position
		var r := notifier.aabb.size.x * 0.5
		if view.grow(r).has_point(Vector2(p.x, -p.y)):
			_set_awake(true)
			return
