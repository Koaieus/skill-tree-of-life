@tool
extends SkillNodeVisual
## The entity core look (#1108): one [Gimbal3D] rig in the viewport's single
## [GimbalWorld], anchored on this Node2D. Worn in a [CorePresence] slot via
## [member CoreClass.core_look]; exists only while a slot wears it, so a
## Blocker or a non-core node costs nothing 3D. A boss is an inherited scene
## with [member style] pinned.
##
## Identity in, look out: `entity_tint` -> rig tint; `radius` -> rig
## `base_radius`; `owner_level` -> [member ring_count]
## ([method Gimbal3D.rings_for_level]); `node_seed` -> [member phase] (golden
## angle, so neighbouring cores never share a pose).
##
## Gate: rig `visible` = in-tree visible AND (revealed OR on screen) — the
## CoreHalos #802 gate; the on-screen half is the holder's
## VisibleOnScreenNotifier3D. The rig is acquired lazily (deferred: an ancestor
## may still be setting up its children) and freed on `_exit_tree`; the holder
## follows this node by `set_notify_transform`. In the editor the rig is built
## only outside the edited scene ([method GimbalWorld.is_live_for]): the sandbox
## panel spins one, a SkillNode in an open .tscn never does.

## The cpu2d gimbal's footprint in disk radii at halo_scale 1 (#804): keeps
## the 3D rig the size the 2D one was.
const FOOTPRINT := 1.434
## Radians; spreads per-node phases evenly (the golden angle).
const GOLDEN_ANGLE := 2.399963

@export var style: Gimbal3D.Style = Gimbal3D.Style.HOLO_GLASS:
	set(value):
		style = value
		if _rig != null:
			_rig.style = value

## Scales the rig outward from the disk.
@export_range(1.0, 3.0, 0.01) var halo_scale: float = 1.8:
	set(value):
		halo_scale = value
		_apply_radius()

## Derived from `owner_level`; never authored.
var ring_count: int = Gimbal3D.rings_for_level(1):
	set(value):
		if ring_count == value:
			return
		ring_count = value
		if _rig != null:
			_rig.ring_count = value

## Radians on the rig's spin clock; derived from `node_seed`.
var phase: float = 0.0:
	set(value):
		if is_equal_approx(phase, value):
			return
		phase = value
		if _rig != null:
			_rig.phase = value

## Out of the fog for the local viewer; forwarded by [CorePresence].
var revealed: bool = true:
	set(value):
		revealed = value
		_refresh_gate()

var _rig: Gimbal3D = null
var _holder: Node3D = null
var _on_screen: bool = false


func _on_identity_changed() -> void:
	ring_count = Gimbal3D.rings_for_level(owner_level)
	phase = wrapf(float(node_seed) * GOLDEN_ANGLE, 0.0, TAU)
	if _rig != null and _rig.tint != entity_tint:
		_rig.tint = entity_tint


func configure(new_radius: float) -> void:
	super(new_radius)
	_apply_radius()


func _notification(what: int) -> void:
	super._notification(what)
	match what:
		NOTIFICATION_ENTER_TREE:
			set_notify_transform(true)
			_acquire.call_deferred()
		NOTIFICATION_EXIT_TREE:
			_release()
		NOTIFICATION_TRANSFORM_CHANGED:
			_sync_holder()
		NOTIFICATION_VISIBILITY_CHANGED:
			_refresh_gate()


## CorePresence travel hook: the look glides in from the old node.
func on_core_travel_start(local_offset: Vector2, duration: float) -> void:
	position = local_offset
	_sync_holder()
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2.ZERO, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _acquire() -> void:
	if _holder != null or not is_inside_tree() or not GimbalWorld.is_live_for(self):
		return
	_rig = Gimbal3D.new()
	_rig.style = style
	_rig.ring_count = ring_count
	_rig.tint = entity_tint
	_rig.phase = phase
	_rig.base_radius = _rig_radius()
	_holder = GimbalWorld.acquire(self).add_rig(_rig, global_position, radius)
	var notifier := _holder.get_node_or_null(^"OnScreen") as VisibleOnScreenNotifier3D
	if notifier != null:
		notifier.screen_entered.connect(_on_screen_changed.bind(true))
		notifier.screen_exited.connect(_on_screen_changed.bind(false))
	_refresh_gate()


func _release() -> void:
	if _holder != null:
		_holder.queue_free()
	_holder = null
	_rig = null
	_on_screen = false


func _on_screen_changed(value: bool) -> void:
	_on_screen = value
	_refresh_gate()


func _refresh_gate() -> void:
	if _rig != null:
		_rig.visible = is_visible_in_tree() and (revealed or _on_screen)


func _sync_holder() -> void:
	if _holder != null:
		_holder.position = GimbalWorld.to_world_3d(global_position)


func _rig_radius() -> float:
	return radius * halo_scale * FOOTPRINT


func _apply_radius() -> void:
	if _rig != null and not is_equal_approx(_rig.base_radius, _rig_radius()):
		_rig.base_radius = _rig_radius()
