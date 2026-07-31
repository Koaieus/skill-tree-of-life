@tool
class_name PoolGauge
extends ColorRect
## Reusable "Arcane Terminal" pool gauge. cell_count == 0 renders a smooth
## continuous bar (Health/Mana/XP); cell_count > 0 renders N skewed
## parallelogram "battery" cells (AP/DP/Move). Every exported value pushes
## to the shader immediately in its setter, so tuning is live (and
## animated — shine, drain-trail) in the Inspector, not just at runtime.

const DRAIN_FADE_TIME := 0.9

## A scripted fill ([method animate_to] or [method play_level_segment]) reached
## its end. One signal for both, because the caller driving a multi-level
## replay needs a single "that beat is done, give me the next" edge — see
## [HeroSigilCard]'s playback state machine (and note it must distinguish
## *which* beat finished itself; this signal doesn't say).
signal fill_finished

## Emitted at the hold instant of a level segment, while the bar is sitting
## full at the cap it just reached and BEFORE it wraps to empty. This is the
## "a level happened" moment — the level badge bump and the LEVEL UP
## announcement hang off this, not off the model's own `leveled_up` (which
## fires the instant XP lands, well ahead of the bar).
signal level_segment_held(new_max: float)

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

## Force battery (cell) rendering even at cell_count 0. A SurplusPoolGauge whose
## pool cap is SET to 0 (Pacifist) still draws cells for its out-of-cap surplus;
## without this, cell_count 0 falls into the smooth-bar branch that ignores
## surplus. Plain vitals bars leave this false.
@export var force_cells: bool = false:
	set(v):
		force_cells = v
		_push(&"force_cells", 1.0 if v else 0.0)

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

## Beat at the full bar before wrapping (#317), long enough to read as "a level
## happened". Deliberately short — an XP bar that flashes and wraps reads
## better than one that sits there, and the LEVEL UP banner (not the gauge)
## carries the weight of the moment. Pacing the banner's ×N stamps to these
## beats needs a Banner hold-extend — see #320.
@export_range(0.0, 1.0, 0.01) var level_up_hold_time: float = 0.15

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
	_push(&"force_cells", 1.0 if force_cells else 0.0)
	_push(&"skew_degrees", skew_degrees)
	_push(&"corner_radius", corner_radius)
	_push(&"cell_gap", cell_gap)

## Animate the bar to a settled `(current, max)` — the everyday move, used for
## XP between level-ups and for health/mana alike (#317; before it, every
## non-level-up change hard-cut).
##
## [b]Increases tween; decreases don't.[/b] A drop assigns `current` straight
## through so the setter's drain-trail branch still fires — freezing the ghost
## at the old value and fading it down is a deliberate effect, and tweening the
## fill under `_suppress_drain` would silently delete it. "No tween" in #317 is
## about the fill, not the ghost.
func animate_to(target_current: float, target_max: float) -> void:
	if _level_tween and _level_tween.is_valid():
		_level_tween.kill()
	if not is_inside_tree() or target_current <= current or level_up_fill_time <= 0.0:
		_suppress_drain = false
		max_value = target_max
		current = target_current
		_end_scripted_fill()
		return
	_suppress_drain = true
	max_value = target_max
	_level_tween = create_tween()
	_level_tween.tween_property(self, ^"current", target_current, level_up_fill_time) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_level_tween.tween_callback(_end_scripted_fill)


## Play ONE level crossing: fill to `fill_to` (the cap just reached), hold there
## while [signal level_segment_held] fires, then wrap to empty and adopt
## `new_max`. Ends with the bar empty at the new cap — the caller plays the next
## segment, or settles with [method animate_to], off [signal fill_finished].
##
## Split per-level (rather than one tween for the whole cascade) so a grant
## landing mid-replay only has to append to the caller's queue: no tween is ever
## killed, so there's no stale "shown" state to rebuild from.
func play_level_segment(fill_to: float, new_max: float) -> void:
	if _level_tween and _level_tween.is_valid():
		_level_tween.kill()
	if not is_inside_tree():
		level_segment_held.emit(new_max)
		max_value = new_max
		current = float(min_value)
		_end_scripted_fill()
		return
	_suppress_drain = true
	_level_tween = create_tween()
	# Phase 1 — fill to full at the cap this level reached.
	_level_tween.tween_property(self, ^"current", fill_to, level_up_fill_time) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 2 — beat at full, and announce from there.
	_level_tween.tween_interval(level_up_hold_time)
	_level_tween.tween_callback(func() -> void: level_segment_held.emit(new_max))
	# Phase 3 — grow the cap and empty the bar (the "wrap").
	_level_tween.tween_callback(func() -> void: max_value = new_max)
	_level_tween.tween_property(self, ^"current", float(min_value), level_up_wrap_time) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_level_tween.tween_callback(_end_scripted_fill)


## One self-contained level-up: fill to the old cap, wrap, fill to the overflow
## the new level opened with. Retained from #154 as the single-level shorthand
## over the two primitives above; the multi-level path drives them directly, so
## this currently has no production caller.
##
## [b]Don't reach for it on a gauge someone else is sequencing.[/b] It chains
## its own one-shot [signal fill_finished] listener, which a driver like
## [HeroSigilCard] would read as one extra beat in its own state machine.
func play_level_up(old_current: float, old_max: float, new_current: float, new_max: float) -> void:
	if not is_inside_tree():
		max_value = new_max
		current = new_current
		return
	_suppress_drain = true
	max_value = old_max
	current = old_current
	_suppress_drain = false
	var settle := func() -> void: animate_to(new_current, new_max)
	fill_finished.connect(settle, CONNECT_ONE_SHOT)
	play_level_segment(old_max, new_max)


## Close out a scripted fill. The signal is emitted DEFERRED, never inline: the
## whole point of [signal fill_finished] is that a caller chains the next beat
## off it, and doing that from inside the finishing tween's own final callback
## would have the new beat kill the tween that is still executing it.
func _end_scripted_fill() -> void:
	_suppress_drain = false
	_emit_fill_finished.call_deferred()


func _emit_fill_finished() -> void:
	fill_finished.emit()


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
