@tool
class_name MenuEdgeView
extends MultiMeshInstance2D

## One edge of the frontmatter menu tree, drawn through the REAL edge shader
## (#569).
##
## [b]It reuses `graph/edge_mesh.gdshader` + `edge_mesh_material.tres`, NOT
## `graph/edge.tscn`[/b] (owner correction, 2026-08-24). Two independent
## reasons the scene cannot be used: [Edge]'s endpoints are typed [SkillNode]
## and really dereferenced on the render path, and [Edge] does not render
## itself at all — `_push_transform()` / `_push_colors()` both hand off to a
## [Graph]-level batched renderer, so the scene needs a [Graph] host as well as
## real endpoints and draws nothing standalone. This hub forbids both classes.
##
## So this is a thin menu-owned renderer over the same shader, and the transform
## convention is copied from `Edge._push_transform()` exactly — the shader
## expands a unit [QuadMesh] whose local X spans the segment and whose Y carries
## a screen-constant width, so getting the convention wrong draws a hairline in
## the wrong place rather than nothing at all.
##
## [b]One instance per edge, not one batch for all of them.[/b] In game that
## would be wrong — `.claude/rules/rendering-performance.md` is explicit that a
## board of a few hundred nodes lives or dies by the draw call, which is why
## [Graph] batches every edge into one shared [MultiMesh]. The frontmatter has
## nine edges; a view per edge buys #570 an ordinary [Node2D] it can tween,
## show and hide, and costs nine draw calls in a menu that draws nothing else.
##
## [b]What is deliberately NOT carried over[/b] from [Edge]: `render_vis_state`
## (fog / sensed / hidden — the menu has no [VisionSystem], so every edge is fed
## a constant [constant Edge.VIS_VISIBLE], which `vision_field_dim` passes
## through untouched while `vision_field_enabled` is false) and `_clamp_code`
## (the Clamp addon, a gameplay thing).
##
## [b]The shape is a sigmoid, not a straight segment[/b] (#592, C3): a cubic
## Bezier whose two control points are pulled purely horizontally off their own
## endpoint, so the curve leaves the parent heading right and arrives at the
## child heading right, with all the vertical travel folded into the middle.
## Drawn as [member curve_segments] straight [QuadMesh] instances chained along
## that curve — still one [MultiMesh], just more than one instance in it; see
## [method curve_point].

## The shader's width is authored in SCREEN pixels and divided by the
## `edge_camera_zoom` global uniform at draw time. Only [GraphCamera] writes
## that global (`scenes/camera_2d.gd`), so a menu whose camera zooms must push
## it itself — see [method push_camera_zoom]. Left alone it keeps whatever the
## last level set, which is a stale width, not a crash.
const CAMERA_ZOOM_UNIFORM := &"edge_camera_zoom"

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _color_from: Color = Color.WHITE
var _color_to: Color = Color.WHITE

## How many straight [QuadMesh] instances approximate the Bezier. The whole
## menu has nine edges, so cost is irrelevant (#592) — tune for smoothness, not
## for draw calls.
@export_range(1, 64, 1) var curve_segments: int = 16:
	set(value):
		curve_segments = maxi(1, value)
		_push_transform()
		_push_colors()

## How far each control point is pulled off its own endpoint, purely along X.
## This is what makes the tangent horizontal at both ends — see [method
## curve_point] — and how pronounced the S-curve reads in the middle.
##
## Raised 60 -> 150 for #596: at 60 the bow was ~2.6% of the chord and the edge
## read as a straight line at menu scale, which defeated the point of it being a
## sigmoid at all. The curve's midpoint is INVARIANT under this knob (both
## coordinates cancel at t=0.5), so the bow shows up off-centre — measure it as
## peak perpendicular deviation from the chord, never as midpoint offset.
@export_range(0.0, 400.0, 1.0) var control_pull: float = 150.0:
	set(value):
		control_pull = value
		_push_transform()

## Whether this edge reads as "on the focus path" — the edge equivalent of
## [member MenuNodeView.allocated]. A lit edge takes the HDR lift below; an
## unlit one desaturates and dims, the same two states [Edge] renders.
@export var lit: bool = false:
	set(value):
		lit = value
		_push_colors()

## Stops of HDR lift a lit edge's chroma takes, and the smaller fixed lift its
## grey floor takes. Named [Emissive] tiers, never hand-picked floats
## (`.claude/rules/hdr-color.md`); the split is `Edge`'s and is explained on
## [method _lifted].
@export_range(0.0, 6.0, 0.05) var lit_glow_stops: float = Emissive.VALUE:
	set(value):
		lit_glow_stops = value
		_push_colors()

## Alpha of a lit / unlit edge. Mirrors `Edge.lit_alpha` / `unlit_alpha`'s
## roles; the numbers are the menu's own, since nothing here fades for fog.
@export_range(0.0, 1.0, 0.01) var lit_alpha: float = 1.0:
	set(value):
		lit_alpha = value
		_push_colors()
@export_range(0.0, 1.0, 0.01) var unlit_alpha: float = 0.55:
	set(value):
		unlit_alpha = value
		_push_colors()

## How far an unlit edge slides toward its own luminance grey, and how much it
## darkens on top. Same treatment as `Edge._display_color`'s unlit branch.
@export_range(0.0, 1.0, 0.01) var unlit_desaturate: float = 0.6:
	set(value):
		unlit_desaturate = value
		_push_colors()
@export_range(0.0, 1.0, 0.01) var unlit_darken: float = 0.35:
	set(value):
		unlit_darken = value
		_push_colors()


func _ready() -> void:
	_ensure_mesh()
	_push_transform()
	_push_colors()


## Runs the edge between two world points, in this node's PARENT space — the
## same convention [Graph] uses when it subtracts its own `global_position`
## before pushing a segment, so an edge view parked anywhere still lands on the
## positions [FrontmatterLayout] solved.
func set_endpoints(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	_push_transform()


## The two endpoint colours. The shader mixes them along `UV.x`, so the
## along-edge gradient falls out for free — exactly as in game.
func set_endpoint_colors(from_color: Color, to_color: Color) -> void:
	_color_from = from_color
	_color_to = to_color
	_push_colors()


## Everything at once, off the two views the edge joins: their positions, their
## archetype colours, and "both ends are on the focus path" as the lit state.
func connect_views(from_view: MenuNodeView, to_view: MenuNodeView) -> void:
	_from = from_view.position
	_to = to_view.position
	_color_from = from_view.display_color()
	_color_to = to_view.display_color()
	lit = from_view.allocated and to_view.allocated
	_push_transform()
	_push_colors()


## Keeps the shader's screen-constant width honest under a zooming camera:
## #570 must call this whenever the frontmatter camera's zoom changes, for the
## same reason [GraphCamera] does in game. A GLOBAL uniform, so this is one
## O(1) write however many edges are on screen.
static func push_camera_zoom(zoom: float) -> void:
	RenderingServer.global_shader_parameter_set(CAMERA_ZOOM_UNIFORM, zoom)


## The instance transform for a segment, straight off `Edge._push_transform()`:
## origin at the midpoint, x-basis rotated along the segment and scaled to its
## length, so the unit quad's local X spans it and its local Y is free for the
## shader to expand into a screen-constant width.
static func segment_transform(from: Vector2, to: Vector2) -> Transform2D:
	var mid := (from + to) * 0.5
	var length := from.distance_to(to)
	var xf := Transform2D((to - from).angle(), mid)
	xf.x *= length
	return xf


## The colour one end renders at. Lit keeps its hue at full alpha and takes the
## HDR lift; unlit desaturates toward its own grey, darkens and fades.
func endpoint_color(base: Color) -> Color:
	var c := base
	if lit:
		c.a = lit_alpha
		return _lifted(c)
	var gray := c.get_luminance()
	c = c.lerp(Color(gray, gray, gray, c.a), unlit_desaturate)
	c = c.darkened(unlit_darken)
	c.a = unlit_alpha
	return c


## The HDR lift a lit edge carries, baked into rgb because a [MultiMesh]
## instance has no `self_modulate` to carry it separately.
##
## Applied relative to the colour's OWN grey floor rather than to the raw
## channels — the reasoning is `Edge._display_color_lifted`'s and is worth not
## re-deriving: scaling all three channels by one factor keeps their ratio, so
## at any real number of stops the weak channels cross the display's clip
## threshold alongside the dominant one and the line reads as flat white with
## the hue gone. Lifting only each channel's rise above the floor blows just the
## dominant one past 1.0, so the edge reads as saturated colour with white-hot
## highlights.
##
## The floor itself still takes a small fixed lift, because an achromatic base
## has no chroma to boost and would otherwise render pixel-identical to its
## unlit sibling.
##
## Deliberately NOT [method Emissive.at]: that helper's final `linear_to_srgb()`
## exists so a `source_color`-hinted shader uniform round-trips through Godot's
## auto-decode. `MultiMesh.set_instance_color` carries no such hint — the value
## is uploaded raw and read straight into `COLOR` — so re-encoding here would
## compress the intended overshoot before the glow pass ever saw it.
func _lifted(c: Color) -> Color:
	var chroma_boost := pow(2.0, lit_glow_stops)
	var floor_boost := pow(2.0, Emissive.VALUE)
	var floor_v: float = minf(c.r, minf(c.g, c.b))
	var lifted_floor: float = floor_v * floor_boost
	return Color(
		lifted_floor + (c.r - floor_v) * chroma_boost,
		lifted_floor + (c.g - floor_v) * chroma_boost,
		lifted_floor + (c.b - floor_v) * chroma_boost,
		c.a,
	)


## [member curve_segments] unit [QuadMesh] instances, (re)sized on demand so a
## caller may configure this view before it enters the tree, and so changing
## [member curve_segments] in the inspector resizes it live. Never authored in
## the `.tscn`: per-instance MultiMesh data is runtime state, and [Graph]
## learned the hard way that it must not reach a saved scene.
func _ensure_mesh() -> void:
	if multimesh != null and multimesh.instance_count == curve_segments:
		return
	var mm := multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = QuadMesh.new()
	mm.instance_count = curve_segments
	mm.visible_instance_count = curve_segments
	multimesh = mm


## This edge's Bezier sampled at `t` (0..1), in the same space `_from`/`_to`
## were given — this node's PARENT space, per [method set_endpoints]. Cubic
## Bezier with both control points pulled purely horizontally off their own
## endpoint by [member control_pull]:
## [codeblock]
## P0 = _from
## P1 = _from + (pull, 0)
## P2 = _to   - (pull, 0)
## P3 = _to
## [/codeblock]
## which makes the tangent at t=0 exactly `3*(P1-P0) = (3*pull, 0)` and the
## tangent at t=1 exactly `3*(P3-P2) = (3*pull, 0)` — pure +X at BOTH ends,
## independent of how far apart or how vertically offset the two endpoints
## are. That is the "leaves going right, arrives going right" shape #592 asks
## for; every real curvature and the whole vertical travel is folded into the
## middle.
##
## Exposed as a pure function — not read back off the [MultiMesh] — because
## per-instance MultiMesh data does not round-trip headless
## (`docs/domain/godot-workflow.md`, the blind spot that hid #413): this is
## what a test asserts against instead.
func curve_point(t: float) -> Vector2:
	var p1 := _from + Vector2(control_pull, 0.0)
	var p2 := _to - Vector2(control_pull, 0.0)
	var u := 1.0 - t
	return (
		_from * (u * u * u)
		+ p1 * (3.0 * u * u * t)
		+ p2 * (3.0 * u * t * t)
		+ _to * (t * t * t)
	)


## The `index`th straight sub-segment's instance transform, in this node's
## local space (subtracting `position`, same convention [method
## instance_transform] uses) — a chord of the Bezier between two adjacent
## samples, stretched exactly as [method segment_transform] treats any other
## straight span.
func segment_instance_transform(index: int) -> Transform2D:
	var t0 := float(index) / float(curve_segments)
	var t1 := float(index + 1) / float(curve_segments)
	return segment_transform(curve_point(t0) - position, curve_point(t1) - position)


func _push_transform() -> void:
	_ensure_mesh()
	for i in curve_segments:
		multimesh.set_instance_transform_2d(i, segment_instance_transform(i))


## `COLOR` carries each instance's own start colour; `INSTANCE_CUSTOM.rgb`
## carries its end colour and its alpha carries the vision state — which is
## why the end colour's own alpha is not sent: both ends always share one
## alpha, exactly as [Edge] packs it. With [member curve_segments] > 1 the raw
## hue is lerped along the WHOLE curve's `t` first and lifted per segment, so
## the along-edge gradient — and the lit HDR lift riding on top of it — stays
## continuous across every instance instead of jumping at segment seams.
func _push_colors() -> void:
	_ensure_mesh()
	for i in curve_segments:
		var t0 := float(i) / float(curve_segments)
		var t1 := float(i + 1) / float(curve_segments)
		var a := endpoint_color(_color_from.lerp(_color_to, t0))
		var b := endpoint_color(_color_from.lerp(_color_to, t1))
		multimesh.set_instance_color(i, a)
		multimesh.set_instance_custom_data(i, Color(b.r, b.g, b.b, Edge.VIS_VISIBLE))
