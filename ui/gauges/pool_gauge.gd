@tool
class_name PoolGauge
extends ColorRect
## Reusable "Arcane Terminal" pool gauge. cell_count == 0 renders a smooth
## continuous bar (Health/Mana/XP); cell_count > 0 renders N skewed
## parallelogram "battery" cells (AP/DP/Move). Every exported value pushes
## to the shader immediately in its setter, so tuning is live (and
## animated — shine, drain-trail) in the Inspector, not just at runtime.

const DRAIN_FADE_TIME := 0.9

@export var current: float = 1.0:
	set(v):
		var old := current
		current = v
		if _suppress_drain:
			# A scripted animation (e.g. the level-up wrap) owns the motion;
			# never spawn a drain trail that would fight it.
			drain_from = v
		elif v < old:
			# Freeze the ghost at the old value, then tween it down to the
			# new one so the loss reads as a fading trail, not a snap.
			drain_from = old
			_animate_drain_to(v)
		else:
			drain_from = v
		_push(&"current", current)

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		_push(&"min_value", v)

@export var max_value: float = 2.0:
	set(v):
		max_value = v
		_push(&"max_value", v)

## Ghost/previous value driving the drain trail. Normally managed
## automatically by the `current` setter; exposed for manual scripting.
@export var drain_from: float = 1.0:
	set(v):
		drain_from = v
		_push(&"drain_from", v)

@export var fill_color: Color = Color(0.7, 0.75, 0.95, 1.0):
	set(v):
		fill_color = v
		_push(&"fill_color", v)

@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		empty_color = v
		_push(&"empty_color", v)

@export var glow_color: Color = Color(1.0, 1.0, 1.0, 0.6):
	set(v):
		glow_color = v
		_push(&"glow_color", v)

@export var drain_color: Color = Color(0.9, 0.3, 0.3, 0.5):
	set(v):
		drain_color = v
		_push(&"drain_color", v)

## Next-turn gain preview — mirror of [member drain_from], but rendered
## *above* `current` instead of below it. Band spans `current` to
## `current + preview_gain`, clamped at `max_value`, in **stat units** (not
## a fraction — the shader derives the fraction itself). `0.0` disables the
## band, which is the resting state, so existing gauges are unaffected.
@export var preview_gain: float = 0.0:
	set(v):
		preview_gain = v
		_push(&"preview_gain", v)

@export var preview_color: Color = Color(1.0, 1.0, 1.0, 0.25):
	set(v):
		preview_color = v
		_push(&"preview_color", v)

@export_range(0.0, 4.0, 0.05) var shine_speed: float = 0.6:
	set(v):
		shine_speed = v
		_push(&"shine_speed", v)

## 0 = smooth continuous bar. N = N skewed parallelogram cells.
@export_range(0.0, 16.0, 1.0) var cell_count: float = 0.0:
	set(v):
		cell_count = v
		_push(&"cell_count", v)

@export_range(-45.0, 45.0, 0.5) var skew_degrees: float = 0.0:
	set(v):
		skew_degrees = v
		_push(&"skew_degrees", v)

@export_range(0.0, 20.0, 0.5) var corner_radius: float = 4.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

@export_range(0.0, 12.0, 0.5) var cell_gap: float = 3.0:
	set(v):
		cell_gap = v
		_push(&"cell_gap", v)

## Level-up animation timings (#154). Fill = each rise (to old cap, then to the
## overflow amount at the new cap); wrap = the snap-to-empty between them.
@export_range(0.0, 1.5, 0.01) var level_up_fill_time: float = 0.35
@export_range(0.0, 0.6, 0.01) var level_up_wrap_time: float = 0.10

var _drain_tween: Tween
var _level_tween: Tween
## Set while a scripted level-up animation drives `current`, to disable the
## drain-trail branch of its setter.
var _suppress_drain: bool = false

func _ready() -> void:
	if material == null:
		material = preload("res://ui/gauges/pool_gauge_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push_all()

func _push_size() -> void:
	_push(&"size", size)

func _push_all() -> void:
	_push(&"current", current)
	_push(&"min_value", min_value)
	_push(&"max_value", max_value)
	_push(&"drain_from", drain_from)
	_push(&"fill_color", fill_color)
	_push(&"empty_color", empty_color)
	_push(&"glow_color", glow_color)
	_push(&"drain_color", drain_color)
	_push(&"preview_gain", preview_gain)
	_push(&"preview_color", preview_color)
	_push(&"shine_speed", shine_speed)
	_push(&"cell_count", cell_count)
	_push(&"skew_degrees", skew_degrees)
	_push(&"corner_radius", corner_radius)
	_push(&"cell_gap", cell_gap)

## Play the XP-style level-up sequence (#154): fill from the pre-level fraction
## up to the OLD cap, snap-empty at the NEW cap, then fill to the overflow amount
## the new level started with. Without this the pool's three synchronous signal
## edits (fill → grow-cap → reset-to-overflow) collapse into one frame and the
## bar reads as jumping *down*. Caller passes the pre-level and post-level state
## because by the time a level-up is observable the pool already holds the final.
func play_level_up(old_current: float, old_max: float, new_current: float, new_max: float) -> void:
	if not is_inside_tree():
		max_value = new_max
		current = new_current
		return
	if _level_tween:
		_level_tween.kill()
	_suppress_drain = true
	max_value = old_max
	current = old_current
	_level_tween = create_tween()
	# Phase 1 — fill to full at the old cap.
	_level_tween.tween_property(self, ^"current", old_max, level_up_fill_time) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 2 — grow the cap and empty the bar (the "wrap").
	_level_tween.tween_callback(func() -> void: max_value = new_max)
	_level_tween.tween_property(self, ^"current", float(min_value), level_up_wrap_time) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Phase 3 — fill to the overflow the new level opened with.
	_level_tween.tween_property(self, ^"current", new_current, level_up_fill_time) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_level_tween.tween_callback(func() -> void: _suppress_drain = false)


func _animate_drain_to(target: float) -> void:
	if not is_inside_tree():
		drain_from = target
		return
	if _drain_tween:
		_drain_tween.kill()
	_drain_tween = create_tween()
	_drain_tween.tween_property(self, ^"drain_from", target, DRAIN_FADE_TIME)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
