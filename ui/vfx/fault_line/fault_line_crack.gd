@tool
class_name FaultLineCrack
extends Node2D

## Fault Line's edge visual: a glowing fissure that tears open along the edge
## the crack spreads over, thick and bright where much Sunder landed and thin
## where little did, sealing (thinning and fading) after it lands. A crit — the
## weak point — lifts it one named tier and shatters the struck node.
##
## Paint-on-top, like [EdgeEnergize]: it never touches `Edge`, `Graph` or the
## edge MultiMesh, and every instance shares ONE material. Per-instance
## channels are the transform (the bar's x-scale is the opening front, its
## y-scale the width) and `modulate` (tint, tier, fade) — never a uniform.
##
## The crack amount is read off the landing's own hits: the Sunder intake
## rider appends a [StatusInstance] whose [member StatusInstance.power] is the
## LANDED stacks once the outcome has been applied, which is all the
## coordinator ever hands a visual. An absolute number, deliberately — not
## [member ScheduleEntry.magnitude], which is normalized per cast and would draw
## a weak cast's seed as thick as a strong one's.
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`,
##              `_on_crit(tier)`, `_on_context(entry)`
##   outbound — [signal finished]

signal finished

const ZLayers = preload("res://ui/z_layers.gd")
const SHATTER_FIELD_SCENE: PackedScene = preload("res://ui/vfx/shatter/shatter_field.tscn")
const SHARED_MATERIAL: ShaderMaterial = preload("res://ui/vfx/fault_line/fault_line_crack_material.tres")
const EDGE_MATERIAL: ShaderMaterial = preload("res://graph/edge_mesh_material.tres")

## Caster identity tint, stamped by the coordinator after launch.
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_apply_look()

## The status whose landed stacks size the crack.
@export var status_id: StringName = &"sunder"

## Landed stacks at which the crack reaches [member max_width] and
## [member max_tier]. Tentative, easy to change.
@export_range(1.0, 100.0, 0.5, "or_greater") var full_crack_stacks: float = 10.0:
	set(value):
		full_crack_stacks = value
		_refresh_crack()

## Width factor (times the shared material's stroke) at zero and at full
## stacks. Tentative, easy to change.
@export_range(0.05, 4.0, 0.05) var min_width: float = 0.5:
	set(value):
		min_width = value
		_refresh_crack()
@export_range(0.05, 4.0, 0.05) var max_width: float = 1.6:
	set(value):
		max_width = value
		_refresh_crack()

## Resting glow at zero and at full stacks — named tiers, lerped between.
@export var min_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		min_tier = value
		_refresh_crack()
@export var max_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		max_tier = value
		_refresh_crack()

## Seconds the landed crack takes to seal (thin and fade) after arrival.
## Bounds concurrency like [member EdgeEnergize.linger_seconds].
@export_range(0.0, 8.0, 0.05) var linger_seconds: float = 1.8
## Width the crack seals down to by the end of the linger, as a fraction of
## its landed width.
@export_range(0.0, 1.0, 0.01) var sealed_width: float = 0.3

## Weak-point crit shatter at the struck node. Tentative, easy to change.
@export_range(1.0, 64.0, 0.5) var shatter_radius: float = 16.0
@export_range(1, 32, 1) var shatter_shards: int = 12
@export_range(0.0, 600.0, 1.0) var shatter_kick: float = 140.0
@export_range(0.05, 4.0, 0.01) var shatter_window: float = 0.7

## World-space endpoints. Derived from the entry by [method _on_context]; a
## sandbox with no entry stamps them itself, in its own parent space.
@export var edge_origin: Vector2 = Vector2.ZERO:
	set(value):
		edge_origin = value
		_place()
@export var edge_target: Vector2 = Vector2.ZERO:
	set(value):
		edge_target = value
		_place()

## Handed to the linger and shatter tweens; a test sets `clock.manual`.
var clock := TweenClock.new()

## Landed stacks this crack draws; set by [method _on_context] or
## [method set_crack].
var crack_stacks: float = 0.0
var crit_tier: int = 0

var _front: float = 0.0
var _alpha: float = 1.0
var _seal: float = 1.0
var _pending: int = 0
var _done_emitted: bool = false
var _arrived: bool = false

@onready var _bar: Sprite2D = %Bar


func _ready() -> void:
	_sync_width()
	z_index = ZLayers.SPELL_VFX
	_place()
	_refresh_crack()


## The edge's authored stroke onto the shared crack material, once — a
## shared-material write, never a per-instance one.
static func _sync_width() -> void:
	var w: Variant = EDGE_MATERIAL.get_shader_parameter(&"width")
	if w is float or w is int:
		SHARED_MATERIAL.set_shader_parameter(&"edge_width", float(w))


## Sets the crack amount and crit tier directly (the sandbox's route; a
## coordinator goes through [method _on_context] / [method _on_crit]).
func set_crack(stacks: float, tier: int = 0) -> void:
	crack_stacks = maxf(stacks, 0.0)
	crit_tier = maxi(tier, 0)
	_refresh_crack()


## 0..1: how full the crack is against [member full_crack_stacks].
func crack_fraction() -> float:
	return clampf(crack_stacks / maxf(full_crack_stacks, 0.001), 0.0, 1.0)


# ---------------------------------------------------------------- duck contract


func _on_context(entry: Variant) -> void:
	if entry == null:
		return
	var stacks := _landed_stacks(entry)
	if stacks >= 0.0:
		crack_stacks = stacks
	var origin_node: Node2D = VfxContext.read_node2d(entry, &"origin")
	var target_node: Node2D = VfxContext.read_node2d(entry, &"target")
	if origin_node != null and target_node != null:
		top_level = true
		edge_origin = origin_node.global_position
		edge_target = target_node.global_position
	_refresh_crack()


func _on_launch() -> void:
	_set_front(0.0)


func _on_progress(t: float) -> void:
	_set_front(t)


func _on_crit(tier: int) -> void:
	crit_tier = maxi(crit_tier, tier)
	_refresh_crack()


func _on_arrival() -> void:
	_set_front(1.0)
	if _arrived:
		return
	_arrived = true
	if crit_tier > 0:
		_shatter()
	if linger_seconds > 0.0:
		_pending += 1
		var tween := clock.tween(self)
		tween.set_parallel(true)
		tween.tween_property(self, ^"_alpha", 0.0, linger_seconds)
		tween.tween_property(self, ^"_seal", sealed_width, linger_seconds)
		tween.chain().tween_callback(_settle_one)
		set_process(true)
	_check_done()


# ------------------------------------------------------------------- internals


## The landed stacks of [member status_id] among the entry's hits, summed; -1
## when the entry carries no hits field at all.
func _landed_stacks(entry: Variant) -> float:
	if not (entry is Object and &"hits" in entry):
		return -1.0
	var total := 0.0
	for hit: Variant in entry.get(&"hits"):
		var status := hit as StatusInstance
		if status != null and status.def != null and status.def.id == status_id:
			total += status.power
	return total


func _shatter() -> void:
	var field: ShatterField = SHATTER_FIELD_SCENE.instantiate()
	# The field hashes its fracture from its own origin and must not rotate:
	# this node is rotated along the edge, so the field escapes it.
	field.top_level = true
	field.window = shatter_window
	field.spawn_tier = Emissive.Tier.ALERT
	add_child(field)
	# The struck node: the far end of the edge in this node's own (rotated)
	# frame, so it is right whether or not the endpoints are world-space.
	var at: Vector2 = to_global(Vector2((edge_target - edge_origin).length(), 0.0))
	field.spawn_shatter(at, shatter_radius, tint, Vector2.ZERO, 0.0, shatter_shards, shatter_kick)
	_pending += 1
	var tween := clock.tween(self)
	tween.tween_method(field.set_elapsed, 0.0, shatter_window, shatter_window)
	tween.tween_callback(_settle_one)


func _settle_one() -> void:
	_pending -= 1
	_check_done()


func _check_done() -> void:
	if _done_emitted or _pending > 0:
		return
	_done_emitted = true
	set_process(false)
	finished.emit.call_deferred()


func _process(_delta: float) -> void:
	_refresh_crack()


func _set_front(value: float) -> void:
	_front = clampf(value, 0.0, 1.0)
	_place()


func _place() -> void:
	if _bar == null:
		return
	var along: Vector2 = edge_target - edge_origin
	position = edge_origin
	if along.length_squared() < 1e-6:
		_bar.scale = Vector2(0.0, 1.0)
		return
	rotation = along.angle()
	var texture_width: float = maxf(1.0, float(_bar.texture.get_width()))
	_bar.scale = Vector2(along.length() * _front / texture_width, _bar.scale.y)


## Width (bar y-scale) and glow (`modulate`) from the crack amount, the crit
## and the seal — the only per-instance writes this class makes.
func _refresh_crack() -> void:
	if _bar == null:
		return
	var f := crack_fraction()
	_bar.scale.y = lerpf(min_width, max_width, f) * _seal
	var stops := lerpf(Emissive.stops(min_tier), Emissive.stops(max_tier), f)
	# The weak point: one named tier up, the same step EdgeEnergize's crit takes.
	if crit_tier > 0:
		stops += Emissive.ALERT - Emissive.VALUE
	_apply_look(stops)


func _apply_look(stops: float = NAN) -> void:
	if not is_inside_tree():
		return
	if is_nan(stops):
		_refresh_crack()
		return
	var col: Color = Emissive.tint(tint, stops)
	col.a = tint.a * clampf(_alpha, 0.0, 1.0)
	modulate = col
