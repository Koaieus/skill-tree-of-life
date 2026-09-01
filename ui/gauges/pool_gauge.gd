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
		if _suppress_drain or _snapping:
			# A scripted animation (e.g. the level-up wrap) owns the motion;
			# never spawn a drain trail that would fight it.
			drain_from = v
		elif v < old:
			# Freeze the ghost at the old value, then tween it down to the
			# new one so the loss reads as a fading trail, not a snap.
			drain_from = old
			_animate_drain_to(v)
			spark_cells(_cell_of(v), _cell_of(old), true, fill_color)
		else:
			drain_from = v
			if v > old:
				# Arriving: the slot it is filling shows `empty_color` behind the
				# fill for as long as the fill is still growing into it.
				spark_cells(_cell_of(old), _cell_of(v), false, empty_color)
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

## EV stops the travelling shine trace is lifted by — the ENERGY half of the
## trace, with [member glow_color] as its hue and that colour's alpha as how far
## the crest mixes over the fill. Landmarks are [Emissive]'s named tiers
## ([code]VALUE[/code] 1.0, [code]ALERT[/code] 2.0, [code]PEAK[/code] 3.0); the
## shader peak-normalizes the hue first (Emissive.tint_peak), so equal stops read
## as equal glow whether the gauge is red, cyan or gold.
##
## Above 0 this is real HDR that the WorldEnvironment bloom pass picks up — it is
## not a self-lit fake, so a viewport with no bloom (an editor dock, a
## SubViewport without [code]use_hdr_2d[/code]) shows only the SDR crest. See
## docs/domain/hdr-color.md.
@export_range(0.0, 3.0, 0.05) var glow_stops: float = 2.5:
	set(v):
		glow_stops = v
		_push(&"glow_stops", v)

## The tier a cell burns at the instant it arrives or leaves, before cooling
## back to [member glow_stops]. [Emissive]'s [code]PEAK[/code] (3.0) is the
## documented "momentary ignition-flash overshoot that relaxes back down", which
## is exactly this — 2.5 is the owner-chosen setting under it.
@export_range(0.0, 3.0, 0.05) var spark_stops: float = 2.5:
	set(v):
		spark_stops = v
		_push(&"spark_stops", v)

## How long one ignition takes to cool from [member spark_stops] to rest.
@export_range(0.05, 2.0, 0.01) var spark_time: float = 0.45

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
##
## [b][member max_fill_time] silently wins.[/b] A level crossing sweeps the
## whole bar, so its loop takes `1.0 / fill_speed` seconds OR this, whichever is
## shorter — dropping `fill_speed` alone to slow a level-up down does nothing
## once the two cross. Raise both.
@export_range(0.0, 1.0, 0.01) var min_fill_time: float = 0.12
@export_range(0.1, 4.0, 0.05) var max_fill_time: float = 1.1

var _drain_tween: Tween
var _level_tween: Tween
## The ignition band — one cell burning at a time, cooling to rest. Composed,
## and shared with [CompositeBarGauge]; see [GaugeSpark].
var _spark := GaugeSpark.new(self, _push)
## Set while a (re)bind is painting a gauge for the first time — see
## [method begin_snap]. Suppresses the drain ghost; [GaugeSpark] carries the
## same window for the spark.
var _snapping: bool = false
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
	_push(&"glow_stops", glow_stops)
	_push(&"spark_stops", spark_stops)
	_spark.push_initial()
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
	# The duration is read against the TARGET span, so `max_value` moves first.
	var from_value := current
	var span_max := target_max
	var duration := _fill_duration(from_value, target_current, span_max)
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
## [b]A segment costs what a segment costs, however many are queued behind
## it.[/b] Compressing a cascade to fit a fixed total was tried and reverted
## (#320, owner call 2026-08-24): XP is the currency the game is denominated in,
## so gaining four levels SHOULD take about twice as long to watch as gaining
## two. Pace the loop with [member fill_speed], not with the queue depth.
func play_level_segment(fill_to: float, new_max: float) -> void:
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


## Open a window in which every write lands with no drain ghost and no ignition
## — the paint a bind or a hot-seat rebind does. A binder's first sync would
## otherwise read the PREVIOUS hero's fill as a spend or a replenish and ignite
## the difference. Always pair with [method end_snap]; a binder that sets several
## values (cap, cells, current, surplus) wants one window around all of them.
func begin_snap() -> void:
	_snapping = true
	_spark.snapping = true


func end_snap() -> void:
	_snapping = false
	_spark.snapping = false


## [method begin_snap] around a single `current` write.
func snap_to(value: float) -> void:
	begin_snap()
	current = value
	end_snap()


## Ignite the strip cells in [code][lo, hi)[/code] — see [method GaugeSpark.ignite].
## Indices are into the RENDERED strip, so a [SurplusPoolGauge]'s trailing
## surplus cells are addressable as [code]cell_count + n[/code]; the band cannot
## be expressed in stat units because the strip mixes two bins.
##
## `color` is the state on the OTHER side of the change — the bin a leaving cell
## came from, or the one an arriving cell is displacing. The shader cannot work
## it out for itself: by the time it draws, the model has already moved, and it
## needs both states to keep the slot occupied for the whole burn.
func spark_cells(lo: float, hi: float, outgoing: bool, color: Color) -> void:
	if _suppress_drain:
		# A scripted fill (a level-up wrap) steps `current` many times; it owns
		# the motion and must not strobe the strip.
		return
	_spark.ignite(lo, hi, outgoing, color, false, spark_time)


## Which strip cell a stat value sits at — the cap-relative fill in cells, which
## is where a `current` move lands. Surplus cells live past `cell_count`.
##
## A pool need not be integral (a regen tick or a fractional modifier can park
## `current` at 3.5), and the shader tests the band against whole cell indices —
## so a raw fractional bound would produce a band no cell ever matches, and the
## spark would silently do nothing for exactly those values. [method spark_cells]
## widens to whole cells for that reason: a partial move ignites the cell it is
## in.
func _cell_of(value: float) -> float:
	var span := max_value - min_value
	if span <= 0.0:
		return 0.0
	return clampf((value - min_value) / span, 0.0, 1.0) * cell_count


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
