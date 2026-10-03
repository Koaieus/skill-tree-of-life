@tool
class_name StatusArrow
extends LightArrow

## A typed arrow (#1351): today's attacker-tinted [LightArrow] shaft plus three
## parts in the STATUS colour — a `%Tip` over the arrowhead, a `%Trail`
## [GPUParticles2D] streaming behind the flight, and a `%Burst` at the impact.
## The base scene every per-type arrow inherits.
##
## [member status_tint] is stamped per shot by [ArrowVolleyCoordinator] from
## the shot's [method AmmoType.first_status_def] `tint` — never authored per scene —
## and lifted to a named [Emissive] tier here: VALUE for the tip, LABEL for the
## particles. A transparent tint (no status) hides all three, leaving exactly a
## [LightArrow].
##
## Per-instance colour rides `modulate` on each emitter over ONE shared
## [ParticleProcessMaterial] per emitter role (the scene's sub-resources), so
## a 30-arrow volley stays batched (`.claude/rules/rendering-performance.md`);
## it adds ≤ 30 emitters for under a second, and nothing per frame beyond them.
##
## [signal finished] waits [method drain_seconds] past the moment the emitters
## stop, by a timer rather than [signal GPUParticles2D.finished]: that signal
## only fires for a `one_shot` emitter, and a headless run never processes
## particles at all, so a wait on it could never end there.

## Shot's status colour (SDR, alpha 0 = none). Setter repaints the parts.
@export var status_tint: Color = Color(0, 0, 0, 0):
	set(v):
		status_tint = v
		_paint_status()
## Tip length as a fraction of the whole arrow (shaft + head). Tentative knob.
@export_range(0.05, 1.0, 0.01) var tip_fraction: float = 0.25:
	set(v):
		tip_fraction = v
		_paint_status()
## Trail particle count. Tentative knob.
@export_range(1, 128) var trail_amount: int = 24:
	set(v):
		trail_amount = v
		_paint_status()
## Seconds a trail particle lives — also how long the trail takes to drain.
## Tentative knob.
@export_range(0.05, 2.0, 0.01) var trail_lifetime: float = 0.25:
	set(v):
		trail_lifetime = v
		_paint_status()

## Set once the trail has been told to stop (arrival or dud); a late launch never restarts it.
var _emit_stopped: bool = false


func _ready() -> void:
	super._ready()
	_paint_status()


func has_status() -> bool:
	return status_tint.a > 0.0


## Seconds from the emitters stopping until the last particle is gone — the
## longest-lived emitter's lifetime.
func drain_seconds() -> float:
	var trail := _trail()
	var burst := _burst()
	return maxf(trail.lifetime if trail != null else 0.0, burst.lifetime if burst != null else 0.0)


func _on_launch() -> void:
	super._on_launch()
	var trail := _trail()
	if trail != null and has_status() and not _emit_stopped:
		trail.emitting = true


## The impact beats arrive just AFTER [method _on_arrival] (the coordinator
## dispatches them off the projectile's `arrived`), so they cancel a burst
## already started: a dud never landed, and an absorbed shot is the defender's
## verdict — a status-colour burst on either would claim the status landed.
func _on_dud() -> void:
	super._on_dud()
	_stop_trail()
	_cancel_burst()
	_paint_status()


func _on_absorbed(gained: bool) -> void:
	super._on_absorbed(gained)
	_cancel_burst()
	_paint_status()


func _cancel_burst() -> void:
	var burst := _burst()
	if burst != null:
		burst.emitting = false


func _on_arrival() -> void:
	var first := not _arrived
	super._on_arrival()
	if not first:
		return
	_stop_trail()
	var burst := _burst()
	if burst != null and has_status() and not _dud and not _absorbed:
		burst.restart()
		burst.emitting = true


## The shaft's fade is done; the particles may still be in the air. The fade
## itself ran `hold + fade` seconds after the emitters stopped at arrival, so
## only the remainder of the drain is waited out — with the shipped hold of
## 2 s the drain has long elapsed by then, so `finished` is never delayed in
## practice; the wait matters only for a short hold.
func _on_faded() -> void:
	var rest := drain_seconds() - (hold_seconds + fade_seconds) if has_status() else 0.0
	if rest > 0.0 and is_inside_tree():
		await get_tree().create_timer(rest).timeout
	_emit_finished()


func _process(delta: float) -> void:
	super._process(delta)
	if _arrived:
		_fade_parts()


func _stop_trail() -> void:
	_emit_stopped = true
	var trail := _trail()
	if trail != null:
		trail.emitting = false


func _paint_status() -> void:
	var tip := _tip()
	var trail := _trail()
	var burst := _burst()
	if tip == null or trail == null or burst == null:
		return
	var shown := has_status()
	var tip_len := tip_fraction * (shaft_length + head_length)
	var half_w := head_width * 0.5 * (tip_len / maxf(head_length, 0.001))
	tip.polygon = PackedVector2Array([Vector2.ZERO, Vector2(-tip_len, half_w), Vector2(-tip_len, -half_w)])
	# An absorbed shot speaks for the defender (see LightArrow._on_absorbed),
	# so the status tip steps aside rather than repainting that verdict.
	tip.visible = shown and not _absorbed
	var tier := Emissive.INERT if _dud else Emissive.VALUE
	var tip_base := status_tint
	if _dud:
		var lum := tip_base.get_luminance()
		tip_base = Color(lum, lum, lum, tip_base.a).lerp(tip_base, 0.25)
	tip.color = Emissive.at(Color(tip_base.r, tip_base.g, tip_base.b, 1.0), tier)
	var glow := Emissive.at(Color(status_tint.r, status_tint.g, status_tint.b, 1.0), Emissive.LABEL)
	trail.visible = shown
	trail.modulate = glow
	burst.visible = shown and not _dud and not _absorbed
	burst.modulate = glow
	if trail.amount != trail_amount:
		trail.amount = trail_amount
	trail.lifetime = trail_lifetime


func _fade_parts() -> void:
	var tip := _tip()
	if tip != null:
		tip.self_modulate.a = clampf(_alpha, 0.0, 1.0)


func _tip() -> Polygon2D:
	return get_node_or_null(^"%Tip") as Polygon2D


func _trail() -> GPUParticles2D:
	return get_node_or_null(^"%Trail") as GPUParticles2D


func _burst() -> GPUParticles2D:
	return get_node_or_null(^"%Burst") as GPUParticles2D
