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
## Unbounded on purpose only for the test's lifetime; the body clears it on
## teardown.
var requested: Array[Dictionary] = []

## Live flights: `{from, to, tint, t}` in layer-local pixels, t in 0..1.
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
	return out


## Arrows in flight right now.
func in_flight() -> int:
	return _flights.size()


## Fly one arrow of [param type_id] from global point [param from] to the
## centre of global rect [param to]; [param on_land] runs on arrival. A
## [param delay] staggers it within its batch.
func fly(type_id: StringName, kind: StringName, from: Vector2, to: Rect2, on_land: Callable = Callable(), delay: float = 0.0) -> void:
	requested.append({"type": type_id, "kind": kind, "from": from, "to": to})
