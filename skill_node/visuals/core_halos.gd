@tool
extends SkillNodeVisual
## Core presence halos (#128): rotate-once 2D marks for a core — the gear a
## Dormant Core wears is this at COG (`core_gear.tscn`). Spikes are explicitly
## excluded — that mark is reserved for the addons system (fortify/plates),
## not core identity. The entity look is the 3D `core_gimbal.tscn`, not a style
## here.
##
## Reads [member SkillNodeVisual.entity_tint]: a core marks "this is YOUR
## nucleus", so it carries ownership, not archetype. Only the halo's own
## translucency is private ([member halo_opacity]).

enum CoreHaloStyle { NONE, RINGS, ORBIT, COG }

## Alpha the halo marks are drawn at — the halo's own material property, kept
## private so the identity color it reads stays a plain opaque tint.
@export_range(0.0, 1.0, 0.01) var halo_opacity: float = 0.8:
	set(value):
		halo_opacity = value
		_redraw_all()

var _halo_color: Color:
	get():
		var c := entity_tint
		c.a = halo_opacity
		return c

@export var halo_style: CoreHaloStyle = CoreHaloStyle.NONE:
	set(value):
		halo_style = value
		_rebuild_spin_layers()
		_refresh_animation()
		_redraw_all()

## Whether this node is out of the fog for the local viewer — pushed down from
## [member SkillNode.revealed] through [method CorePresence.set_revealed]
## (#802). Half of the animation gate below; the other half is on-screen.
var revealed: bool = true:
	set(value):
		if revealed == value:
			return
		revealed = value
		_refresh_animation()

## Scales the halo radius outward from the rim.
@export_range(1.0, 2.0, 0.01) var halo_scale: float = 1.3:
	set(value):
		halo_scale = value
		_resize_notifier()
		_redraw_all()

@export_range(0.5, 3.0, 0.01) var spin_speed: float = 1.0

## Rigid-geometry layers (#802) — one CanvasItem per independently-spinning
## ring, drawn once and animated by `rotation`. Empty for NONE.
var _spin_layers: Array[Node2D] = []

## Exported setters run while the scene is still being instantiated (before
## this node has entered the tree), and rebuilding the layer children then only
## to rebuild them again at READY is pure churn — so the rebuild is deferred to
## READY and every later style change does it for real.
var _ready_done: bool = false

## Last colour the layers were painted with — see [method _on_identity_changed]
## for why this component needs an idempotence guard. Alpha < 0 is an
## impossible [Color], so the first identity write always lands.
var _painted_color: Color = Color(0.0, 0.0, 0.0, -1.0)

## Set by [VisibleOnScreenNotifier2D] below. Starts false: the notifier emits
## `screen_entered` on its first served frame when it IS on screen, so the
## honest default is "assume not, let the server say otherwise" — a fail-OPEN
## default would leave every off-screen halo animating forever, which is the
## bug (#802).
var _on_screen: bool = false
var _notifier: VisibleOnScreenNotifier2D = null

const SPIN_LAYER_SCENE: PackedScene = preload("res://skill_node/visuals/halo_spin_layer.tscn")
## RINGS' per-ring radius step; its outermost ring is the widest mark drawn.
const RINGS_STEP := 0.18
const RINGS_COUNT := 3


## Shared clock, scaled at read time so a spin_speed tweak never jumps the phase.
func _spin() -> float:
	return anim_time * spin_speed


## One tick of the shared clock ([method SkillNodeVisual._on_anim_tick]): write
## each layer's `rotation` and DON'T queue a redraw — Godot keeps the geometry
## it already has, so an animating COG costs a float write instead of a rebuilt
## circle + ten teeth (#802).
func _on_anim_tick() -> void:
	_apply_spin_rotations()


## A full invalidation: the spin layers hold baked geometry, so they redraw
## only here — whenever an INPUT changes (style, radius, scale, tint, opacity).
func _redraw_all() -> void:
	for layer in _spin_layers:
		if is_instance_valid(layer):
			layer.queue_redraw()


## Identity and radius both feed BAKED geometry, so both channels are
## IDEMPOTENT: the composite loop-sets every identity value into every child on
## any one of them changing, and `SkillNode._sync_visuals()` re-pushes
## `configure(radius)` wholesale. An unguarded repaint here would silently undo
## #802 the day either ran per frame — the whole win is painting once.
##
## `_halo_color` is the ONLY identity this component draws with, so comparing
## it is exact, not a heuristic.
func _on_identity_changed() -> void:
	var color := _halo_color
	if color == _painted_color:
		return
	_painted_color = color
	_redraw_all()


func configure(new_radius: float) -> void:
	if is_equal_approx(new_radius, radius):
		return
	super(new_radius)
	_resize_notifier()
	_redraw_all()


## Wires the gate up on ready and re-evaluates it whenever this node's
## visibility-in-tree changes (the composite hides the whole [CorePresence]
## for a non-core node and the whole ShaderStack for a sensed one).
##
## `super._notification` first — the base uses NOTIFICATION_READY to re-assert
## the process flag, and `_refresh_animation` is what decides its real value.
func _notification(what: int) -> void:
	super._notification(what)
	match what:
		NOTIFICATION_READY:
			_ready_done = true
			_rebuild_spin_layers()
			_refresh_animation()
		NOTIFICATION_VISIBILITY_CHANGED:
			_refresh_animation()


## The animation gate (#802): animate iff the item is actually in the tree AND
## someone could see it. The on-screen half is deliberately OR'd rather than
## AND'ed with `revealed`: the notifier is the engine's answer and can be
## silent (headless, a fresh frame), and `revealed` alone is the safe fallback.
func _refresh_animation() -> void:
	var live := halo_style != CoreHaloStyle.NONE and is_visible_in_tree()
	_sync_notifier(live)
	set_animating(live and (revealed or _on_screen))


## The on-screen half of the gate, from the engine rather than a per-frame
## rect test in GDScript. Created LAZILY and only while the halo could animate
## at all, so a hidden halo never carries a dead notifier child (#172/#238).
##
## `show_rect` is off because the engine paints the notifier's rect in
## translucent magenta under `Engine.is_editor_hint()`, and the sandbox tabs
## run INSIDE the editor process (#892). Not an alpha-0 modulate instead: the
## canvas cull pass returns on `modulate.a < 0.007` BEFORE it evaluates the
## visibility notifier, which would silently kill this gate in the real game.
func _sync_notifier(wanted: bool) -> void:
	if wanted == (_notifier != null):
		return
	if wanted:
		_notifier = VisibleOnScreenNotifier2D.new()
		_notifier.show_rect = false
		_notifier.screen_entered.connect(_on_screen_changed.bind(true))
		_notifier.screen_exited.connect(_on_screen_changed.bind(false))
		add_child(_notifier)
		_resize_notifier()
	else:
		_notifier.queue_free()
		_notifier = null
		_on_screen = false


func _on_screen_changed(value: bool) -> void:
	_on_screen = value
	_refresh_animation()


## The notifier's rect covers the WIDEST mark this component draws — RINGS'
## outermost ring — so a halo never stops animating before it leaves the screen.
func _resize_notifier() -> void:
	if _notifier == null:
		return
	var r := radius * halo_scale * (1.0 + float(RINGS_COUNT - 1) * RINGS_STEP)
	_notifier.rect = Rect2(-r, -r, r * 2.0, r * 2.0)


## Rebuilds the rigid spin layers for the current style. Each entry is one
## independently-rotating CanvasItem: RINGS gets three (its rings run at 1.0 /
## 1.5 / 2.0), ORBIT and COG one each, NONE none.
func _rebuild_spin_layers() -> void:
	if not _ready_done:
		return
	for layer in _spin_layers:
		if is_instance_valid(layer):
			layer.queue_free()
	_spin_layers.clear()
	for spec in _spin_layer_rates():
		var layer: Node2D = SPIN_LAYER_SCENE.instantiate()
		layer.layer_index = _spin_layers.size()
		layer.spin_rate = spec
		add_child(layer)
		_spin_layers.append(layer)
	_apply_spin_rotations()


func _spin_layer_rates() -> PackedFloat32Array:
	match halo_style:
		CoreHaloStyle.RINGS:
			return PackedFloat32Array([1.0, 1.5, 2.0])
		CoreHaloStyle.ORBIT:
			return PackedFloat32Array([1.0])
		CoreHaloStyle.COG:
			return PackedFloat32Array([0.3])
		_:
			return PackedFloat32Array()


func _apply_spin_rotations() -> void:
	var spin := _spin()
	for layer in _spin_layers:
		layer.rotation = spin * layer.spin_rate


## CorePresence travel hook (#128, docs/domain/skillnode-emblem.md): the halo
## physically glides — offset in from `local_offset`, tween back to
## Vector2.ZERO. See core_presence.gd for the duck-typed contract.
func on_core_travel_start(local_offset: Vector2, duration: float) -> void:
	position = local_offset
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2.ZERO, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Paints ONE rigid spin layer, in its own un-rotated frame — the layer's
## `rotation` supplies the angle. Called from [HaloSpinLayer._draw]
## (duck-typed) so all the style knowledge stays here.
func paint_spin_layer(target: CanvasItem, index: int) -> void:
	var halo_color := _halo_color
	var base_r := radius * halo_scale
	match halo_style:
		CoreHaloStyle.RINGS:
			_paint_dashed_circle(target, base_r * (1.0 + index * RINGS_STEP), 10, halo_color)
		CoreHaloStyle.ORBIT:
			_paint_orbit(target, base_r, halo_color)
		CoreHaloStyle.COG:
			_paint_cog(target, base_r, halo_color)


func _paint_orbit(target: CanvasItem, base_r: float, halo_color: Color) -> void:
	target.draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	# The orbiting dots read as solid beads on a translucent track.
	var dot_color := Color(halo_color, 1.0)
	var dot_count := 4
	for i in dot_count:
		target.draw_circle(polar_point(base_r, (TAU / dot_count) * i), 2.5, dot_color)


func _paint_cog(target: CanvasItem, base_r: float, halo_color: Color) -> void:
	target.draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	var teeth := 10
	var tooth_len := base_r * 0.12
	for i in teeth:
		var theta := (TAU / teeth) * i
		target.draw_line(polar_point(base_r, theta), polar_point(base_r + tooth_len, theta), halo_color, 2.0, true)


func _paint_dashed_circle(target: CanvasItem, r: float, dash_count: int, color: Color) -> void:
	var step := TAU / dash_count
	for i in dash_count:
		var a0 := i * step
		target.draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, color, 1.5, true)
