@tool
class_name ArrowFlightLayer
extends Control
## The ranged panel's flight overlay: arrows visibly move between an
## [AmmoCard]'s pile and the [VolleyBar], and a reload's gain drops onto the
## piles. Presentation only — the plan list is already final when a flight is
## requested, a flight never gates it, and a landing only calls back into the
## view that asked (the bar's `on_arrow_placed` / `on_arrow_released`).
##
## Geometry is GLOBAL: the caller hands the source point and destination rect
## it read from [method AmmoCard.pile_anchor] / [method VolleyBar.segment_rect];
## the layer converts them into its own space. The body is the only caller and
## decides how many fly through the pure [method diff].

const TO_BAR := &"to_bar"
const TO_PILE := &"to_pile"
const RELOAD := &"reload"

## Seconds one arrow takes from source to destination (tentative).
@export_range(0.05, 2.0) var flight_secs: float = 0.25
## Most arrows one change flies, per type and direction — a drag of 300 flies
## this many, not 300 (tentative).
@export_range(1, 64) var max_flights_per_change: int = 8
## Seconds a card's stock counter takes to tween to its new value (tentative).
@export_range(0.0, 2.0) var counter_tween_secs: float = 0.3
## Delay between successive arrows of one batch, s (tentative).
@export_range(0.0, 0.2) var stagger_secs: float = 0.03
## Drawn shaft length and width, px (tentative).
@export var shaft_size: Vector2 = Vector2(4.0, 14.0)

## Every flight requested, `{type, kind, from, to}` — the log tests read.
## The body clears it through [method clear] on teardown.
var requested: Array[Dictionary] = []

## Live flights: `{from, to, tint, t, tween}` in layer-local pixels, t in 0..1.
var _flights: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Pure: the flights a change of the plan list from [param old_ammo] to
## [param new_ammo] (`[{type, count}]`) asks for, per type, at most
## [param cap] each. An added arrow flies TO_BAR into its slot in the NEW
## list (`total` = new n); a removed one flies TO_PILE out of its slot in the
## OLD list (`total` = old n). The last slots of the type's run move.
## Returns `[{type, dir, index, total}]`.
static func diff(old_ammo: Array, new_ammo: Array, cap: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var old_runs := _runs(old_ammo)
	var new_runs := _runs(new_ammo)
	var old_n := _total(old_ammo)
	var new_n := _total(new_ammo)
	var types: Array = new_runs.keys()
	for t in old_runs:
		if not types.has(t):
			types.append(t)
	for t in types:
		var o: Vector2i = old_runs.get(t, Vector2i.ZERO)
		var nw: Vector2i = new_runs.get(t, Vector2i.ZERO)
		var delta := nw.y - o.y
		if delta > 0:
			for i in range(nw.x + nw.y - mini(delta, cap), nw.x + nw.y):
				out.append({"type": t, "dir": TO_BAR, "index": i, "total": new_n})
		elif delta < 0:
			for i in range(o.x + o.y - mini(-delta, cap), o.x + o.y):
				out.append({"type": t, "dir": TO_PILE, "index": i, "total": old_n})
	return out


## `{type: Vector2i(start, count)}` — each type's run in a plan list.
static func _runs(ammo: Array) -> Dictionary:
	var out := {}
	var at := 0
	for entry in ammo:
		var c := int(entry.count)
		out[StringName(entry.type)] = Vector2i(at, c)
		at += c
	return out


static func _total(ammo: Array) -> int:
	var n := 0
	for entry in ammo:
		n += int(entry.count)
	return n


## Arrows in flight right now.
func in_flight() -> int:
	return _flights.size()


## Fly one arrow of [param type_id] from global point [param from] to the
## centre of global rect [param to]; [param on_land] runs on arrival. A
## [param delay] staggers it within its batch.
func fly(type_id: StringName, kind: StringName, from: Vector2, to: Rect2, on_land: Callable = Callable(), delay: float = 0.0) -> void:
	requested.append({"type": type_id, "kind": kind, "from": from, "to": to})
	var inv := get_global_transform().affine_inverse()
	var flight := {
		"from": inv * from,
		"to": inv * to.get_center(),
		"tint": VolleyBar.TYPE_TINTS.get(type_id, VolleyBar.FALLBACK_TINT),
		"t": 0.0,
	}
	_flights.append(flight)
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(_advance.bind(flight), 0.0, 1.0, flight_secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_land.bind(flight, on_land))
	flight["tween"] = tw


## Drop every live flight without landing it (a rebind, a teardown).
func clear() -> void:
	for f: Dictionary in _flights:
		var tw: Tween = f.get("tween")
		if tw != null and tw.is_valid():
			tw.kill()
	_flights.clear()
	requested.clear()
	queue_redraw()


func _advance(t: float, flight: Dictionary) -> void:
	flight["t"] = t
	queue_redraw()


func _land(flight: Dictionary, on_land: Callable) -> void:
	_flights.erase(flight)
	queue_redraw()
	if on_land.is_valid():
		on_land.call()


## A shaft per flight, pointing along its path, on a gentle arc.
func _draw() -> void:
	for f: Dictionary in _flights:
		var t: float = f["t"]
		if t <= 0.0:
			continue
		var a: Vector2 = f["from"]
		var b: Vector2 = f["to"]
		var lift := -minf(40.0, a.distance_to(b) * 0.25) * 4.0 * t * (1.0 - t)
		var pos := a.lerp(b, t) + Vector2(0.0, lift)
		var dir := (b - a).normalized() if a != b else Vector2.UP
		var half := dir * shaft_size.y * 0.5
		draw_line(pos - half, pos + half, f["tint"] as Color, shaft_size.x)
