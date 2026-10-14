@tool
class_name ExplosiveBarrelVisual
extends AddonVisual
## One segment of the barrel stack: barrels draw a "database flowchart"
## cylinder pile standing in elevation on the carrier's rim, one segment per
## barrel, segment i drawn by barrel i and stacked below the ones before it.
## A segment is lit (filled in the addon's identity hue) while the carrier
## holds more than i charges, and a hollow outline once that charge is spent.
## A structure, so it stands on a bearing off the rim, never on the centre
## (docs/domain/addon-visual-registers.md); lower-left, clear of the
## watchtower's lower-right default and the bars straight up. The index and
## the charge count are read off the parent [ExplosiveBarrelAddon], which
## redraws this on the carrier's status and addon changes.

## Where on the rim the stack stands, clockwise from +X in screen space.
@export_range(-180.0, 180.0, 1.0) var stand_bearing_deg: float = 135.0:
	set(value):
		stand_bearing_deg = value
		queue_redraw()
## Segment width, as a fraction of the carrier radius.
@export_range(0.1, 1.0, 0.01) var segment_width: float = 0.42:
	set(value):
		segment_width = value
		queue_redraw()
## Segment body height (between its two rims), × the carrier radius.
@export_range(0.05, 0.6, 0.01) var segment_height: float = 0.16:
	set(value):
		segment_height = value
		queue_redraw()
## Outline width of a spent segment, in pixels.
@export_range(0.5, 4.0, 0.25) var outline_width: float = 1.5:
	set(value):
		outline_width = value
		queue_redraw()

const _STAND_RADIUS := 1.0
const _RIM_SQUASH := 0.32  # ellipse ry / rx for the cylinder rims
const _SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const _SPENT_ALPHA := 0.55
const _SIDE_DARKEN := 0.35


func _draw() -> void:
	var addon := get_parent() as ExplosiveBarrelAddon
	var index := 0
	var lit := true
	var hue := Color(0.95, 0.55, 0.2)
	if addon != null:
		hue = addon.tint
		if addon.carrier != null:
			index = maxi(addon.barrel_index(), 0)
			lit = addon.charges() > float(index)
	var r := radius
	var hw := r * segment_width * 0.5
	var h := r * segment_height
	var ry := hw * _RIM_SQUASH
	var foot := Vector2.from_angle(deg_to_rad(stand_bearing_deg)) * (r * _STAND_RADIUS)
	# Segment i hangs i bodies below the footing segment.
	var top := foot + Vector2(0.0, float(index) * h - h)
	var bottom := top + Vector2(0.0, h)
	if index == 0:
		_ellipse(foot + Vector2(0.0, ry), hw * 1.25, ry * 1.1, _SHADOW_COLOR)
	if lit:
		var side := hue.darkened(_SIDE_DARKEN)
		_ellipse(bottom, hw, ry, side)
		draw_rect(Rect2(top.x - hw, top.y, hw * 2.0, h), side)
		_ellipse(top, hw, ry, hue)
	else:
		var line := Color(hue, _SPENT_ALPHA)
		_ellipse_outline(top, hw, ry, line)
		_ellipse_outline(bottom, hw, ry, line, true)
		draw_line(top + Vector2(-hw, 0.0), bottom + Vector2(-hw, 0.0), line, outline_width)
		draw_line(top + Vector2(hw, 0.0), bottom + Vector2(hw, 0.0), line, outline_width)


func _ellipse(centre: Vector2, rx: float, ry: float, color: Color) -> void:
	draw_colored_polygon(_ellipse_points(centre, rx, ry, 0.0, TAU), color)


func _ellipse_outline(centre: Vector2, rx: float, ry: float, color: Color, lower_half := false) -> void:
	var pts := _ellipse_points(centre, rx, ry, 0.0, PI) if lower_half \
			else _ellipse_points(centre, rx, ry, 0.0, TAU)
	if not lower_half:
		pts.append(pts[0])
	draw_polyline(pts, color, outline_width, true)


func _ellipse_points(centre: Vector2, rx: float, ry: float, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 20
	for i in steps + (0 if is_equal_approx(to - from, TAU) else 1):
		var t := from + (to - from) * float(i) / float(steps)
		pts.append(centre + Vector2(cos(t) * rx, sin(t) * ry))
	return pts
