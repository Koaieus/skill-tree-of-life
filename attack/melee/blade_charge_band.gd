@tool
class_name BladeChargeBand
extends Node2D

## One bead per charge, evenly spaced on a ring centred in a band of
## [member BladeStyle.charge_band_width] × radius just inside the rim; while a
## spend flares, one more bead sits in the next slot, swelling and fading. A
## popped piece draws nothing (the pop and its shards are the read).

var _radius: float = 32.0
var _inner_radius: float = 24.0
var _charges: int = 0
var _spend_progress: float = 0.0
var _style: BladeStyle = null
var _popped: bool = false


func configure(r: float, inner_r: float, charges: int, spend_progress: float,
		style: BladeStyle, popped: bool) -> void:
	_radius = r
	_inner_radius = inner_r
	_charges = charges
	_spend_progress = spend_progress
	_style = style
	_popped = popped
	queue_redraw()


func _draw() -> void:
	var flaring := _spend_progress > 0.0 and _spend_progress < 1.0
	if _style == null or _popped or (_charges <= 0 and not flaring):
		return
	var width := _style.charge_band_width * _radius
	var ring := maxf(_inner_radius - width * 0.5, 0.0)
	var bead := width * 0.5
	var colour := _style.charge_color()
	var slots := _charges + (1 if flaring else 0)
	for k in slots:
		var angle := -PI / 2.0 + TAU * float(k) / float(slots)
		var at := Vector2.from_angle(angle) * ring
		if k < _charges:
			draw_circle(at, bead, colour, true, -1.0, true)
		else:
			var flare := colour
			flare.a *= 1.0 - _spend_progress
			draw_circle(at, bead * (1.0 + _spend_progress), flare, true, -1.0, true)
