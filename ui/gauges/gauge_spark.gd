class_name GaugeSpark
extends RefCounted
## The segment sweep behind the segmented gauges (#882): a gauge's DISPLAYED
## value never jumps to the model's — it tweens there linearly at a constant
## per-cell step, so spending four Movement points recedes one cell at a time
## over four steps and a refill grows back the same way. The shader draws the
## cell the edge is crossing as a partial cell, and while any sweep runs the
## strip is "hot" (`spark_energy` 1.0, the crossing cell lifted to
## `spark_stops`); once the last sweep lands it cools back to rest.
##
## Composed by [PoolGauge] and [CompositeBarGauge] rather than inherited — the
## two share no base beyond [ColorRect] and have quite different models (one
## current/max pool vs. four proportional buckets), but the per-cell pacing, the
## hot/cool tween and the uniforms it drives are one thing. The shader half
## lives in `gauge_spark.gdshaderinc`, included by both.
##
## [b]The HUD only ever reacts.[/b] Every caller sweeps off a stat that has
## already moved — never off an input, an intent, or a preview. Under
## host-authoritative sync that means a confirmed command moves the pool and
## every peer's gauge sweeps the same cells off the same signal; the tween is
## animation and gates nothing, so a slow client cannot hold up the world (see
## `.claude/rules/presentation-clock.md` and `.claude/rules/multiplayer-sync.md`).

var _host: CanvasItem
## `_push(param, value)` — the host's own shader-parameter setter, so a gauge
## that duplicates its material still drives the copy it is actually rendering.
var _push: Callable
## The host gauge's own `TweenClock` — every tween this spark creates goes
## through it (#1065), so a test steps the host's `clock` by hand instead of
## the real clock. Passed in rather than read off `_host`: `_host` is a bare
## `CanvasItem` and reaching into a duck-typed `.clock` is the reach-in
## `TweenClock` exists to delete.
var _clock: TweenClock
## One tween per swept property, so a `current` sweep and a `surplus` sweep on
## the same gauge run side by side and a repeat on the same property replaces
## only its own.
var _sweeps: Dictionary = {}
## Sweeps waiting their turn, property -> bound `_start` call, in arrival order.
## Sweeps are SERIAL: a Movement spend that empties the surplus bin and then
## bites into `current` fires two signals on two properties, and the spec is
## that the next cell never starts before the one before it is gone — so the
## second waits, and a repeat on a waiting property replaces its target.
var _pending: Dictionary = {}
var _cool_tween: Tween

## While true every [method sweep] snaps — the window a binder opens around its
## first paint. A bind is not a spend: repainting the gauge from a different
## hero's pools (hot-seat handover) would otherwise animate the difference as
## points just spent or just gained.
var snapping: bool = false

var energy: float = 0.0:
	set = _set_energy


func _init(host: CanvasItem, push: Callable, clock: TweenClock) -> void:
	_host = host
	_push = push
	_clock = clock


func _set_energy(v: float) -> void:
	energy = v
	_push.call(&"spark_energy", v)


## Push the resting state onto a freshly-duplicated material.
func push_initial() -> void:
	_push.call(&"spark_energy", energy)
	_push.call(&"spark_edge", 0.0)
	_push.call(&"spark_out", 0.0)


## Tween `property` on `target` (normally the host's displayed value) to `to`,
## linearly, over `|cells| * step_time` seconds — the distance is handed in as
## strip cells because only the caller knows how its units map onto the strip,
## and SIGNED: negative means the run is leaving (a spend), so the shader lifts
## only the receding partial cell and not the neighbour it settles beside.
## `edge` names which of the gauge's boundaries is moving (`spark_edge`, a
## per-shader enumeration) so the shader lifts the right crossing cell. Hot for
## the whole sweep; cools over `cool_time` once the last running sweep lands.
##
## Snaps instead (sets the property straight through, no lift) while
## [member snapping], off-tree, or when there is nothing to travel. A sweep
## already running on the same property is replaced FROM WHERE IT IS: a second
## spend continues the recession, a refill mid-spend turns the edge around.
func sweep(target: Object, property: NodePath, to: Variant, cells: float,
		step_time: float, cool_time: float, edge: float = 0.0) -> void:
	var duration := absf(cells) * step_time
	if snapping or _host == null or not _host.is_inside_tree() or duration <= 0.0:
		snap(target, property, to)
		return
	if is_sweeping() and not _sweeps.has(property):
		_pending[property] = _start.bind(target, property, to, cells, duration, cool_time, edge)
		return
	_start(target, property, to, cells, duration, cool_time, edge)


func _start(target: Object, property: NodePath, to: Variant, cells: float,
		duration: float, cool_time: float, edge: float) -> void:
	_stop(property)
	_pending.erase(property)
	_push.call(&"spark_edge", edge)
	_push.call(&"spark_out", 1.0 if cells < 0.0 else 0.0)
	if _cool_tween and _cool_tween.is_valid():
		_cool_tween.kill()
	energy = 1.0
	var tween := _clock.tween(_host)
	tween.tween_property(target, property, to, duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(_on_landed.bind(property, cool_time))
	_sweeps[property] = tween


## Set `property` straight through, abandoning any sweep running on it — and
## the heat with it, if that was the last one: a snapped strip has nothing
## crossing to be hot about.
func snap(target: Object, property: NodePath, to: Variant) -> void:
	_stop(property)
	_pending.erase(property)
	if snapping:
		_pending.clear()
	target.set_indexed(property, to)
	if not is_sweeping():
		if _cool_tween and _cool_tween.is_valid():
			_cool_tween.kill()
		energy = 0.0


## True while any sweep is still travelling.
func is_sweeping() -> bool:
	for t: Tween in _sweeps.values():
		if t and t.is_valid():
			return true
	return false


func _stop(property: NodePath) -> void:
	var prior: Tween = _sweeps.get(property)
	if prior and prior.is_valid():
		prior.kill()
	_sweeps.erase(property)


func _on_landed(property: NodePath, cool_time: float) -> void:
	_sweeps.erase(property)
	if is_sweeping():
		return
	if not _pending.is_empty():
		var next: Callable = _pending[_pending.keys()[0]]
		next.call()
		return
	if _cool_tween and _cool_tween.is_valid():
		_cool_tween.kill()
	if cool_time <= 0.0:
		energy = 0.0
		return
	_cool_tween = _clock.tween(_host)
	_cool_tween.tween_property(self, ^"energy", 0.0, cool_time) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
