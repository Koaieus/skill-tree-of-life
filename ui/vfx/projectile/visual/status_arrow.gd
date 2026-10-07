@tool
class_name StatusArrow
extends LightArrow

## A typed arrow (#1351): today's attacker-tinted [LightArrow] shaft plus its
## [ArrowPart] children in the STATUS colour. The base scene carries the plain
## look — an [ArrowTip], an [ArrowShedEmitter] trail and an
## [ArrowImpactEmitter] burst — and every per-type arrow is an inherited scene
## that configures or adds parts (`docs/domain/aspect-cell-authoring.md`
## § Arrow). This script only drives the parts; it never names one.
##
## [member status_tint] is stamped per shot by [ArrowVolleyCoordinator] from
## the shot's [method AmmoType.first_status_def] `tint` — never authored per
## scene. Each part lifts it to its own [Emissive] tier. A transparent tint (no
## status) hides every part, leaving exactly a [LightArrow].
##
## The lifecycle: launch → parts launch; arrival → parts stop; the
## coordinator's verdict follows — `_on_dud()`, or `_on_absorbed(gained)` —
## and then, for any landing that was not a dud, `_on_impact(ctx)` with the
## landing's [ArrowImpactContext], which reaches the parts only on a landing
## that counted (not a dud, not absorbed). So an impact never starts and
## then has to be withdrawn.
##
## [signal finished] waits [method drain_seconds] past the moment the parts
## stop, by a timer rather than [signal GPUParticles2D.finished]: that signal
## only fires for a `one_shot` emitter, and a headless run never processes
## particles at all, so a wait on it could never end there.

## Shot's status colour (SDR, alpha 0 = none). Setter repaints the parts.
@export var status_tint: Color = Color(0, 0, 0, 0):
	set(v):
		status_tint = v
		_paint_parts()

## Set once the parts have been told to stop (arrival or dud); a late launch never restarts them.
var _stopped: bool = false


func _ready() -> void:
	super._ready()
	_paint_parts()


func has_status() -> bool:
	return status_tint.a > 0.0


func parts() -> Array[ArrowPart]:
	var out: Array[ArrowPart] = []
	for child in get_children():
		if child is ArrowPart:
			out.append(child)
	return out


## Seconds from the parts stopping until the last of them is gone — the
## longest part's.
func drain_seconds() -> float:
	var longest := 0.0
	for part in parts():
		longest = maxf(longest, part.drain_seconds())
	return longest


func _on_launch() -> void:
	super._on_launch()
	if not has_status() or _stopped:
		return
	for part in parts():
		part.launch()


func _on_arrival() -> void:
	var first := not _arrived
	super._on_arrival()
	if first:
		_stop_parts()


## The landing counted for the attacker: play the impact parts at [param ctx].
## A dud never landed and an absorbed shot is the defender's verdict — a
## status impact on either would claim the status landed.
func _on_impact(ctx: ArrowImpactContext) -> void:
	if not has_status() or _dud or _absorbed:
		return
	for part in parts():
		part.arrive(ctx)


func _on_dud() -> void:
	super._on_dud()
	_stop_parts()
	_paint_parts()


func _on_absorbed(gained: bool) -> void:
	super._on_absorbed(gained)
	_paint_parts()


## The shaft's fade is done; the particles may still be in the air. The fade
## itself ran `hold + fade` seconds after the parts stopped at arrival, so
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
		var a := clampf(_alpha, 0.0, 1.0)
		for part in parts():
			if part.fades_with_shaft:
				part.self_modulate.a = a


func _stop_parts() -> void:
	_stopped = true
	for part in parts():
		part.stop()


func _paint_parts() -> void:
	for part in parts():
		part.paint(status_tint, _dud, _absorbed)
