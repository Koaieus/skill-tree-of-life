@tool
class_name CatalystBarrelVisual
extends AddonVisual
## One segment of the barrel stack: barrels draw a pile of violet crystals
## standing in elevation on the carrier's rim, one crystal per barrel, crystal
## i drawn by barrel i and stacked below the ones before it. A crystal is lit
## (a faceted fill in the addon's identity hue) while the carrier holds more
## than i charges, and a hollow outline once that charge is spent.
## A structure, so it stands on a bearing off the rim, never on the centre
## (docs/domain/addon-visual-registers.md); lower-left, clear of the
## watchtower's lower-right default and the bars straight up. The index and
## the charge count are read off the parent [CatalystBarrelAddon], which
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
const _SHOULDER := 0.28  # where the facets break, as a fraction of the body height
const _SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const _SPENT_ALPHA := 0.55
const _SIDE_DARKEN := 0.35
const _FACET_LIGHTEN := 0.3


func _draw() -> void:
	var addon := get_parent() as CatalystBarrelAddon
	var index := 0
	var lit := true
	var hue := Color(0.67, 0.5, 1.0)
	if addon != null:
		hue = addon.tint
		if addon.carrier != null:
			index = maxi(addon.barrel_index(), 0)
			lit = addon.charges() > float(index)
	var r := radius
	var hw := r * segment_width * 0.5
	var h := r * segment_height
	var foot := Vector2.from_angle(deg_to_rad(stand_bearing_deg)) * (r * _STAND_RADIUS)
	# Crystal i hangs i bodies below the footing crystal; its tips overshoot the body.
	var top := foot + Vector2(0.0, float(index) * h - h)
	var bottom := top + Vector2(0.0, h)
	var tip := h * 0.6
	var shoulder := top.y + h * _SHOULDER
	var apex := Vector2(top.x, top.y - tip)
	var base := Vector2(top.x, bottom.y + tip * 0.4)
	var left_s := Vector2(top.x - hw, shoulder)
	var right_s := Vector2(top.x + hw, shoulder)
	var left_b := Vector2(top.x - hw, bottom.y)
	var right_b := Vector2(top.x + hw, bottom.y)
	if index == 0:
		draw_colored_polygon(PackedVector2Array([foot + Vector2(-hw * 1.2, h * 0.5),
				foot + Vector2(0.0, h * 0.5 + hw * 0.3), foot + Vector2(hw * 1.2, h * 0.5),
				foot + Vector2(0.0, h * 0.5 - hw * 0.3)]), _SHADOW_COLOR)
	if lit:
		var side := hue.darkened(_SIDE_DARKEN)
		draw_colored_polygon(PackedVector2Array([apex, right_s, right_b, base, left_b, left_s]), side)
		draw_colored_polygon(PackedVector2Array([apex, left_s, left_b, base]), hue)
		draw_colored_polygon(PackedVector2Array([apex, left_s, Vector2(top.x, shoulder)]),
				hue.lightened(_FACET_LIGHTEN))
	else:
		var line := Color(hue, _SPENT_ALPHA)
		var ring := PackedVector2Array([apex, right_s, right_b, base, left_b, left_s, apex])
		draw_polyline(ring, line, outline_width, true)
