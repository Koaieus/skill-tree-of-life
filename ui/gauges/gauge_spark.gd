class_name GaugeSpark
extends RefCounted
## The ignition band behind the segmented gauges: a cell that just changed hands
## burns at the shader's `spark_stops` and cools to the gauge's resting glow.
## Spend a Movement point and that cell lights and collapses away; replenish and
## it grows in hot and settles.
##
## Composed by [PoolGauge] and [CompositeBarGauge] rather than inherited — the
## two share no base beyond [ColorRect] and have quite different models (one
## current/max pool vs. four proportional buckets), but the band, its cooling
## tween and the uniforms it drives are one thing. The shader half lives in
## `gauge_spark.gdshaderinc`, included by both.
##
## [b]The HUD only ever reacts.[/b] Every caller ignites off a stat that has
## already moved — never off an input, an intent, or a preview. Under
## host-authoritative sync that means a confirmed command moves the pool and
## every peer's gauge ignites the same cells off the same signal; the tween is
## animation and gates nothing, so a slow client cannot hold up the world (see
## `.claude/rules/presentation-clock.md` and `.claude/rules/multiplayer-sync.md`).

## Band indices are into the RENDERED strip — see the shaderinc's `spark_lo`.
var _host: CanvasItem
## `_push(param, value)` — the host's own shader-parameter setter, so a gauge
## that duplicates its material still drives the copy it is actually rendering.
var _push: Callable
var _tween: Tween
var _lo: float = 0.0
var _hi: float = 0.0
var _out: bool = false

## While true every [method ignite] is dropped — the window a binder opens
## around its first paint. A bind is not a spend: repainting the gauge from a
## different hero's pools (hot-seat handover) would otherwise read the
## difference as points just spent or just gained.
var snapping: bool = false

var energy: float = 0.0:
	set = _set_energy


func _init(host: CanvasItem, push: Callable) -> void:
	_host = host
	_push = push


func _set_energy(v: float) -> void:
	energy = v
	_push.call(&"spark_energy", v)


## Push the resting state onto a freshly-duplicated material.
func push_initial() -> void:
	_push.call(&"spark_energy", energy)


## Ignite the strip cells in `[lo, hi)`. `outgoing` for cells being spent or
## healed away (drawn in `color`, then collapsed), otherwise for cells arriving.
## `anchor_right` picks which edge of its own slot a cell grows out of: the fill
## direction (left) for everything that reads left-to-right, right for the
## trailing wounded/staked runs.
##
## Bounds are widened to whole cells. A pool need not be integral — a regen tick
## or a fractional modifier can park `current` at 3.5 — and the shader tests the
## band against whole cell indices, so a raw fractional bound would produce a
## band no cell ever matches and the spark would silently do nothing, for
## exactly those values and no others.
func ignite(lo: float, hi: float, outgoing: bool, color: Color,
		anchor_right: bool = false, duration: float = 0.45) -> void:
	if snapping or _host == null or not _host.is_inside_tree():
		return
	lo = floorf(lo + 0.001)
	hi = ceilf(hi - 0.001)
	if hi - lo <= 0.001 or duration <= 0.0:
		return
	if _tween and _tween.is_valid() and _out == outgoing:
		# Same direction, still burning: widen the band rather than restarting on
		# the newest cell alone, which would snap the first cell from hot to gone.
		lo = minf(lo, _lo)
		hi = maxf(hi, _hi)
	_lo = lo
	_hi = hi
	_out = outgoing
	_push.call(&"spark_lo", lo)
	_push.call(&"spark_hi", hi)
	_push.call(&"spark_out", 1.0 if outgoing else 0.0)
	_push.call(&"spark_anchor_right", 1.0 if anchor_right else 0.0)
	_push.call(&"spark_color", color)
	if _tween:
		_tween.kill()
	energy = 1.0
	_tween = _host.create_tween()
	_tween.tween_property(self, ^"energy", 0.0, duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
