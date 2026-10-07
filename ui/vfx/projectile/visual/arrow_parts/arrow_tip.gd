@tool
class_name ArrowTip
extends ArrowPart

## The status-coloured head drawn over the shaft's arrowhead: point at the
## origin, body toward −X. [member fade_to_shaft] runs the colour from the head
## at [member tier] to transparent at the back, so the shaft shows through
## (poison's neon tip). A dud draws flat, desaturated, at [constant Emissive.INERT].

enum Shape {
	## A triangle — the arrowhead itself.
	POINTED,
	## A truncated wedge: a flat nose a third of the width.
	BLUNT,
	## A round knob the width of the head.
	CLUB,
}

@export var shape: Shape = Shape.POINTED:
	set(v):
		shape = v
		queue_redraw()
## Length back from the point, world pixels.
@export_range(1.0, 64.0, 0.5) var length: float = 12.0:
	set(v):
		length = v
		queue_redraw()
## Width at the back, world pixels.
@export_range(1.0, 64.0, 0.5) var width: float = 10.0:
	set(v):
		width = v
		queue_redraw()
@export var tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(v):
		tier = v
		queue_redraw()
## Colour runs from the head at [member tier] to transparent at the back.
@export var fade_to_shaft: bool = false:
	set(v):
		fade_to_shaft = v
		queue_redraw()
## Alpha pulses per second while flying; 0 = steady. Stops at the strike.
@export_range(0.0, 12.0, 0.1) var pulse_hz: float = 0.0:
	set(v):
		pulse_hz = v
		set_process(pulse_hz > 0.0 and not _stopped)
## How far a pulse dips the alpha, 0–1.
@export_range(0.0, 1.0, 0.01) var pulse_depth: float = 0.5

var _tint: Color = Color(0, 0, 0, 0)
var _dud: bool = false
var _stopped: bool = false
var _clock: float = 0.0


func _init() -> void:
	show_on_dud = true
	fades_with_shaft = true


func _ready() -> void:
	set_process(pulse_hz > 0.0)


func paint(tint: Color, dud: bool, absorbed: bool) -> void:
	super.paint(tint, dud, absorbed)
	_tint = tint
	_dud = dud
	queue_redraw()


func stop() -> void:
	_stopped = true
	set_process(false)
	modulate.a = 1.0


func _process(delta: float) -> void:
	_clock += delta
	modulate.a = 1.0 - pulse_depth * (0.5 - 0.5 * cos(TAU * pulse_hz * _clock))


func outline() -> PackedVector2Array:
	var h := width * 0.5
	match shape:
		Shape.BLUNT:
			var nose := h / 3.0
			return PackedVector2Array([Vector2(0, -nose), Vector2(0, nose), Vector2(-length, h), Vector2(-length, -h)])
		Shape.CLUB:
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append(Vector2(-h + cos(a) * h, sin(a) * h))
			return pts
	return PackedVector2Array([Vector2.ZERO, Vector2(-length, h), Vector2(-length, -h)])


func _draw() -> void:
	if _tint.a <= 0.0:
		return
	var pts := outline()
	if _dud:
		var lum := _tint.get_luminance()
		var spent := Color(lum, lum, lum, 1.0).lerp(Color(_tint.r, _tint.g, _tint.b, 1.0), 0.25)
		draw_colored_polygon(pts, Emissive.at(spent, Emissive.INERT))
		return
	var head := ArrowPart.lit(_tint, tier)
	if not fade_to_shaft:
		draw_colored_polygon(pts, head)
		return
	var tail := Color(_tint.r, _tint.g, _tint.b, 0.0)
	var back := maxf(length, width) if shape == Shape.CLUB else length
	var cols := PackedColorArray()
	for p in pts:
		cols.append(head.lerp(tail, clampf(-p.x / back, 0.0, 1.0)))
	draw_polygon(pts, cols)
