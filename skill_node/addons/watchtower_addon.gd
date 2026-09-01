@tool
class_name WatchtowerAddon
extends SkillNodeAddon

## The one addon that is a BUILDING rather than a shell, and it is drawn as
## one: a lattice tower standing in elevation on the carrier's rim, roof and
## railing above, legs planted on a contact shadow.
##
## [b]Why this one breaks the concentric habit.[/b] [BunkerAddon] and
## [FortificationAddon] armour the node itself, so they become part of its
## shell and are drawn in plan, as bands. Watchtower doesn't change what the
## node is made of — it grants `vision_range` and `range`, i.e. it projects
## outward — so it is a structure standing ON the territory, and the honest
## projection for that is elevation. The split is the rule, not a compromise:
## shell in plan, building in elevation.
##
## [b]It stands on the rim, not on the middle.[/b] The retired art pasted the
## tooltip icon across the centre of the disk — simultaneously the busiest
## region on the node (the CARVE slot, docs/domain/skillnode-emblem.md) and a
## projection clash, a side-view building laid flat over a dome lit from above.
##
## [b]Bearing is constrained, not aesthetic.[/b] Straight up is taken:
## `skill_node.tscn` parks `HealthBar` at y −59..−46 and `CoreHealthBar` at
## y −44..−28, both spanning x ±35, and `FloatAnchor` sits at (0, −50). The
## default lower-right bearing puts the whole silhouette below y ≈ −21, clear
## of both bands, while keeping the tower's feet in contact with the rim.
##
## [b]Built as bold closed shapes, with the lattice as detail on top.[/b] At
## the zoom where a few hundred nodes share the screen, thin many-part glyphs
## fragment into noise and solid silhouettes hold (.claude/rules/icon-assets.md
## makes the same point about baked icons). So the legs, cabin and roof are
## filled polygons that survive minification, and the X-bracing is drawn over
## them as lines that simply fade out — losing detail, never the shape.

## Where on the rim the tower plants its feet, measured clockwise from +X in
## screen space (so positive is downward). The default puts it lower-right;
## see the bearing note above before moving it upward.
@export_range(-180.0, 180.0, 1.0) var stand_bearing_deg: float = 45.0:
	set(value):
		stand_bearing_deg = value
		queue_redraw()
## Tower height from footing to railing, as a fraction of the carrier radius.
## Roof and cabin stack above this.
@export_range(0.4, 2.0, 0.05) var tower_height: float = 0.88:
	set(value):
		tower_height = value
		queue_redraw()
## Cross-brace tiers between the legs. Pure detail — it disappears when small.
@export_range(0, 6, 1) var brace_tiers: int = 3:
	set(value):
		brace_tiers = value
		queue_redraw()

## Every dimension below is a fraction of the carrier radius, so the tower
## scales with whatever `configure_visual` hands us.
const _FOOT_HALF := 0.28
const _TOP_HALF := 0.17
const _LEG_WIDTH := 0.10
const _RAIL_HALF := 0.30
const _RAIL_HEIGHT := 0.08
const _CABIN_HALF := 0.20
const _CABIN_HEIGHT := 0.25
const _ROOF_HALF := 0.33
const _ROOF_HEIGHT := 0.19
## How far up the rim the footing sits. Just under 1.0 so the feet bite into
## the rim rather than floating off it.
const _STAND_RADIUS := 0.94

const _TIMBER := Color(0.33, 0.30, 0.27)
const _TIMBER_LIT := Color(0.60, 0.55, 0.47)
const _ROOF_COLOR := Color(0.24, 0.22, 0.21)
const _BRACE_COLOR := Color(0.20, 0.18, 0.16)
const _WINDOW_COLOR := Color(0.05, 0.05, 0.07)
const _SHADOW_COLOR := Color(0.02, 0.02, 0.03, 0.5)

var _radius: float = 32.0


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
	queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return

	var r := _radius
	var base := Vector2.from_angle(deg_to_rad(stand_bearing_deg)) * (r * _STAND_RADIUS)

	var foot_half := r * _FOOT_HALF
	var top_half := r * _TOP_HALF
	var leg_w := r * _LEG_WIDTH
	var h := r * tower_height

	# Contact shadow — an ellipse on the rim, drawn first. Without it the tower
	# reads as pasted over the node instead of standing on it.
	_draw_ellipse(base, foot_half * 1.45, foot_half * 0.42, _SHADOW_COLOR)

	# Legs: two splayed trapezoids. Left one catches the house light (which
	# comes from upper-left, see LightingStyle.highlight_position).
	var left_leg := PackedVector2Array([
		base + Vector2(-foot_half, 0.0),
		base + Vector2(-foot_half + leg_w, 0.0),
		base + Vector2(-top_half + leg_w * 0.85, -h),
		base + Vector2(-top_half, -h),
	])
	var right_leg := PackedVector2Array([
		base + Vector2(foot_half - leg_w, 0.0),
		base + Vector2(foot_half, 0.0),
		base + Vector2(top_half, -h),
		base + Vector2(top_half - leg_w * 0.85, -h),
	])
	draw_colored_polygon(left_leg, _TIMBER_LIT)
	draw_colored_polygon(right_leg, _TIMBER)

	# X-bracing between the legs. Detail tier: it is meant to vanish at
	# distance, so it is never load-bearing for the silhouette.
	if brace_tiers > 0:
		for i in brace_tiers:
			var t0 := float(i) / float(brace_tiers)
			var t1 := float(i + 1) / float(brace_tiers)
			var y0 := -h * t0
			var y1 := -h * t1
			var x0 := lerpf(foot_half, top_half, t0) - leg_w * 0.5
			var x1 := lerpf(foot_half, top_half, t1) - leg_w * 0.5
			var brace_w := maxf(1.0, r * 0.035)
			draw_line(
				base + Vector2(-x0, y0), base + Vector2(x1, y1), _BRACE_COLOR, brace_w
			)
			draw_line(
				base + Vector2(x0, y0), base + Vector2(-x1, y1), _BRACE_COLOR, brace_w
			)
			# The horizontal tie at the top of each tier.
			draw_line(
				base + Vector2(-x1, y1), base + Vector2(x1, y1), _BRACE_COLOR, brace_w
			)

	# Railing platform — wider than the cabin, which is what makes a tower
	# silhouette a tower rather than a post.
	var rail_h := r * _RAIL_HEIGHT
	var rail_half := r * _RAIL_HALF
	draw_rect(Rect2(base + Vector2(-rail_half, -h - rail_h), Vector2(rail_half * 2.0, rail_h)), _TIMBER_LIT)

	# Cabin + its lookout window.
	var cab_half := r * _CABIN_HALF
	var cab_h := r * _CABIN_HEIGHT
	var cab_top := -h - rail_h - cab_h
	draw_rect(Rect2(base + Vector2(-cab_half, cab_top), Vector2(cab_half * 2.0, cab_h)), _TIMBER)
	draw_rect(
		Rect2(
			base + Vector2(-cab_half * 0.55, cab_top + cab_h * 0.25),
			Vector2(cab_half * 1.1, cab_h * 0.42)
		),
		_WINDOW_COLOR
	)

	# Pitched roof, overhanging the cabin on both sides.
	var roof_half := r * _ROOF_HALF
	var roof_h := r * _ROOF_HEIGHT
	draw_colored_polygon(
		PackedVector2Array([
			base + Vector2(-roof_half, cab_top),
			base + Vector2(roof_half, cab_top),
			base + Vector2(0.0, cab_top - roof_h),
		]),
		_ROOF_COLOR
	)


## Filled ellipse as a polygon — Godot's CanvasItem has `draw_circle` but no
## squashed variant, and the contact shadow has to be flat to read as ground.
func _draw_ellipse(centre: Vector2, rx: float, ry: float, color: Color) -> void:
	const _SEGMENTS := 16
	var poly := PackedVector2Array()
	for i in _SEGMENTS:
		var theta := TAU * float(i) / float(_SEGMENTS)
		poly.append(centre + Vector2(cos(theta) * rx, sin(theta) * ry))
	draw_colored_polygon(poly, color)
