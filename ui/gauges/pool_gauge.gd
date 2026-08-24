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

## Floor on a budget-compressed segment — see [method play_level_segment].
const MIN_SEGMENT_TIME := 0.30

## Constant-rate fills, in **bar fractions per second** (#320). At 0.9, an empty
## bar sweeps to full in ~1.1s and a gain of a tenth of the bar takes a tenth of
## that. `0` disables it: every fill then runs for a flat `level_up_fill_time`.
##
## [b]Rate, not duration, is what makes a gain's SIZE legible.[/b] Under a fixed
## time a 2%-of-bar tick crawls invisibly and a 60% gain sweeps in the same third
## of a second — the animation says nothing about how much you got, and a big
## gain reads as a snap to full no matter which easing curve you pick. Duration
## proportional to distance is the reward-bar convention (XP, quest progress),
## and it's why the climb is worth animating at all.
##
## Feedback bars are the opposite case and deliberately stay at `0`: for health
## and mana you need to know *that* you were hit before you know by how much, so
## a short front-loaded ease-out beats a legible one. Only the XP gauge opts in.
@export_range(0.0, 4.0, 0.05) var fill_speed: float = 0.0

## Floor and ceiling on a rate-derived duration — a sliver still reads as motion,
## a full sweep still ends. Both ignored when [member fill_speed] is 0.
@export_range(0.0, 1.0, 0.01) var min_fill_time: float = 0.12
@export_range(0.1, 4.0, 0.05) var max_fill_time: float = 1.1

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
## [param time_budget] caps the fill, as in [method play_level_segment]. `0` is
## natural pace and is what an ordinary gain uses; the settle at the end of a
## budgeted cascade passes what is left of that cascade's budget, since a replay
## is not over until the bar has stopped moving.
func animate_to(target_current: float, target_max: float,
		time_budget: float = 0.0) -> void:
	if _level_tween and _level_tween.is_valid():
		_level_tween.kill()
	# The duration is read against the TARGET span, so `max_value` moves first.
	var from_value := current
	var span_max := target_max
	var duration := _fill_duration(from_value, target_current, span_max)
	if time_budget > 0.0:
		duration = minf(duration, maxf(time_budget, min_fill_time))
	if not is_inside_tree() or target_current <= current or duration <= 0.0:
		_suppress_drain = false
		max_value = target_max
		current = target_current
		_end_scripted_fill()
		return
	_suppress_drain = true
	max_value = target_max
	_level_tween = create_tween()
	_level_tween.tween_property(self, ^"current", target_current, duration) \
			.set_ease(_fill_ease()).set_trans(_fill_trans())
	_level_tween.tween_callback(_end_scripted_fill)


## Play ONE level crossing: fill to `fill_to` (the cap just reached), hold there
## while [signal level_segment_held] fires, then wrap to empty and adopt
## `new_max`. Ends with the bar empty at the new cap — the caller plays the next
## segment, or settles with [method animate_to], off [signal fill_finished].
##
## Split per-level (rather than one tween for the whole cascade) so a grant
## landing mid-replay only has to append to the caller's queue: no tween is ever
## killed, so there's no stale "shown" state to rebuild from.
##
## [param time_budget] caps the whole segment (fill + hold + wrap). `0` means
## natural pace. A cascade is what needs this: at the natural rate four levels
## run five-plus seconds, and the replay has to stay inside the couple of
## seconds a player will actually watch — so the DRIVER divides its budget by
## how many levels are still queued and hands each segment its share (see
## [XpTrack]). Expressed as a ceiling rather than a fixed duration precisely so
## the single-level case is untouched: one level is under budget already, keeps
## its rate-derived fill, and so keeps saying how much XP it was.
func play_level_segment(fill_to: float, new_max: float,
		time_budget: float = 0.0) -> void:
	if _level_tween and _level_tween.is_valid():
		_level_tween.kill()
	if not is_inside_tree():
		level_segment_held.emit(new_max)
		max_value = new_max
		current = float(min_value)
		_end_scripted_fill()
		return
	var fill_time := _fill_duration(current, fill_to, max_value)
	var hold_time := level_up_hold_time
	var wrap_time := level_up_wrap_time
	if time_budget > 0.0:
		# Never below MIN_SEGMENT_TIME: compressed past that, a level stops
		# being an event at all.
		var allowed := maxf(time_budget, MIN_SEGMENT_TIME)
		var beat := hold_time + wrap_time
		if fill_time + beat > allowed:
			# The FILL absorbs the compression, and the beat at full gives
			# ground last — the beat is the moment the level happens, and a
			# cascade that scaled everything uniformly would spend its budget
			# animating four bars and showing none of the four levels.
			if allowed - beat >= min_fill_time:
				fill_time = allowed - beat
			else:
				# Not even room for a visible fill plus the authored beat:
				# floor the fill and let the beat take what is left, keeping
				# hold and wrap in their authored proportion.
				fill_time = min_fill_time
				var room := maxf(allowed - fill_time, 0.0)
				var k := room / beat if beat > 0.0 else 0.0
				hold_time *= k
				wrap_time *= k
	_suppress_drain = true
	_level_tween = create_tween()
	# Phase 1 — fill to full at the cap this level reached. Rate-derived like any
	# other fill: this is the path a levelling gain actually takes, so leaving it
	# on a flat duration would keep exactly the "shoots to full" it's here to fix.
	# Measured against the OLD cap, which is what `fill_to` is denominated in.
	_level_tween.tween_property(self, ^"current", fill_to, fill_time) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(_fill_trans())
	# Phase 2 — beat at full, and announce from there.
	_level_tween.tween_interval(hold_time)
	_level_tween.tween_callback(func() -> void: level_segment_held.emit(new_max))
	# Phase 3 — grow the cap and empty the bar (the "wrap").
	_level_tween.tween_callback(func() -> void: max_value = new_max)
	_level_tween.tween_property(self, ^"current", float(min_value), wrap_time) \
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


## How long a fill covering `from_value` → `to_value` should take, against a bar
## whose top is `span_max`. Flat `level_up_fill_time` unless [member fill_speed]
## opts into a constant rate.
func _fill_duration(from_value: float, to_value: float, span_max: float) -> float:
	if fill_speed <= 0.0:
		return level_up_fill_time
	var span := span_max - min_value
	if span <= 0.0:
		return min_fill_time
	return clampf(absf(to_value - from_value) / span / fill_speed, min_fill_time, max_fill_time)


## A constant-rate climb wants a curve that is near-linear through the middle and
## only softens at the ends — cubic's swoosh would put the speed back in. Fixed
## duration keeps its original cubic, so health and mana are untouched.
func _fill_trans() -> Tween.TransitionType:
	return Tween.TRANS_SINE if fill_speed > 0.0 else Tween.TRANS_CUBIC


func _fill_ease() -> Tween.EaseType:
	return Tween.EASE_IN_OUT if fill_speed > 0.0 else Tween.EASE_OUT


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
