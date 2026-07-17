@tool
extends SkillNodeVisual
## Core presence halos (#128): concentric halo marks scaled for "this is a
## nucleus" presence. Spikes are explicitly excluded — that mark is
## reserved for the addons system (fortify/plates), not core identity.
##
## Reads [member SkillNodeVisual.entity_tint]: a core marks "this is YOUR
## nucleus", so it carries ownership, not archetype. Only the halo's own
## translucency is private ([member halo_opacity]).

enum CoreStyle { NONE, RINGS, ORBIT, GIMBAL, COG }

## Alpha the halo marks are drawn at — the halo's own material property, kept
## private so the identity color it reads stays a plain opaque tint.
@export_range(0.0, 1.0, 0.01) var halo_opacity: float = 0.8:
	set(value):
		halo_opacity = value
		_redraw_all()

var _halo_color: Color:
	get():
		var c := entity_tint
		c.a = halo_opacity
		return c

@export var core: CoreStyle = CoreStyle.NONE:
	set(value):
		core = value
		set_animating(core != CoreStyle.NONE)
		_redraw_all()

## Scales the halo radius outward from the rim.
@export_range(1.0, 2.0, 0.01) var halo_scale: float = 1.3:
	set(value):
		halo_scale = value
		_redraw_all()

@export_range(0.5, 3.0, 0.01) var spin_speed: float = 1.0

## GIMBAL only: how many nested rings the gyroscope has. The owner asked for
## this to be tunable ("a real gyroscope with N spin axis").
@export_range(2, 5, 1) var gimbal_ring_count: int = 3:
	set(value):
		gimbal_ring_count = value
		_redraw_all()

## GIMBAL only: each ring's hoop wall half-width (along its own spin axis) as
## a fraction of its own radius — controls how much it reads as a tube/band
## vs. a thin wire.
@export_range(0.02, 0.3, 0.01) var gimbal_band_width: float = 0.12:
	set(value):
		gimbal_band_width = value
		_redraw_all()

## GIMBAL's back layer (see core_halos.tscn) draws whatever passes BEHIND the
## SkillNode's own disk. It borrows this node's geometry/draw helpers below
## rather than duplicating them, so front and back can't drift apart.
@onready var _back_layer: Node2D = $GimbalBack

const GIMBAL_SEGMENTS := 48
## Local spin axis per ring, expressed in its PARENT ring's frame (composed
## via quaternion multiplication below) — never the ring's own normal (Z),
## which would just be an invisible in-plane spin. Alternating RIGHT/UP is
## what makes nested rings read as orthogonal/interlocking rather than
## parallel, like the reference armillary-sphere read.
const GIMBAL_AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.RIGHT, Vector3.UP, Vector3.RIGHT]
const GIMBAL_RATE_BASE := 0.35
const GIMBAL_GLOW_WIDTH := 3.0
## Per-ring radius stagger (inner/mid/outer), same shape as RINGS' 0.18 step.
const GIMBAL_RADIUS_STEP := 0.22


## Shared clock, scaled at read time so a spin_speed tweak never jumps the phase.
func _spin() -> float:
	return anim_time * spin_speed


## Keeps the GIMBAL back layer's own redraw in lockstep with this node's —
## without this, the back layer only redraws once (or never) and the far
## arcs freeze mid-spin while the front half keeps animating.
func _process(delta: float) -> void:
	super._process(delta)
	if core == CoreStyle.GIMBAL and is_instance_valid(_back_layer):
		_back_layer.queue_redraw()


func _redraw_all() -> void:
	queue_redraw()
	if core == CoreStyle.GIMBAL and is_instance_valid(_back_layer):
		_back_layer.queue_redraw()


## Whether GIMBAL is the active preset — the back layer checks this via duck
## typing (it doesn't statically type its parent as CoreHalos) so this class
## doesn't need a `class_name`, matching every other leaf component in this
## family.
func is_gimbal_active() -> bool:
	return core == CoreStyle.GIMBAL


func _draw() -> void:
	if core == CoreStyle.NONE:
		return
	var halo_color := _halo_color
	var base_r := radius * halo_scale
	match core:
		CoreStyle.RINGS:
			_draw_rings(base_r, halo_color)
		CoreStyle.ORBIT:
			_draw_orbit(base_r, halo_color)
		CoreStyle.GIMBAL:
			_draw_gimbal(base_r, halo_color)
		CoreStyle.COG:
			_draw_cog(base_r, halo_color)


func _draw_rings(base_r: float, halo_color: Color) -> void:
	for i in 3:
		var r := base_r * (1.0 + i * 0.18)
		var rate := 1.0 + i * 0.5
		_draw_dashed_circle(r, _spin() * rate, 10, halo_color)


func _draw_orbit(base_r: float, halo_color: Color) -> void:
	draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	# The orbiting dots read as solid beads on a translucent track.
	var dot_color := Color(halo_color, 1.0)
	var dot_count := 4
	for i in dot_count:
		var theta := _spin() + (TAU / dot_count) * i
		draw_circle(polar_point(base_r, theta), 2.5, dot_color)


## Real gyroscope, not a faked tilt: each ring is a hoop (uncapped cylinder
## slice) at its own staggered radius; ring i's orientation is ring (i-1)'s
## orientation composed with ring i's own local spin (a quaternion chain), so
## the outer ring spins independently and every inner ring's pivot is
## mounted on the one outside it — the literal mechanism of a gimbal, not a
## phase offset.
## See _gimbal_runs()/_draw_run_on() for the shared geometry this and
## core_halos_back.gd (the "passes behind the disk" layer) both draw from.
func _draw_gimbal(base_r: float, halo_color: Color) -> void:
	var runs := _gimbal_runs(base_r, halo_color)
	for run in runs["front"]:
		_draw_run_on(self, run, halo_color)


func _draw_cog(base_r: float, halo_color: Color) -> void:
	draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	var teeth := 10
	var tooth_len := base_r * 0.12
	for i in teeth:
		var theta := _spin() * 0.3 + (TAU / teeth) * i
		draw_line(polar_point(base_r, theta), polar_point(base_r + tooth_len, theta), halo_color, 2.0, true)


func _draw_dashed_circle(r: float, offset: float, dash_count: int, color: Color) -> void:
	var step := TAU / dash_count
	for i in dash_count:
		var a0 := i * step + offset
		draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, color, 1.5, true)


## Pure geometry — no draw_* calls — so both the front layer (this node) and
## the back layer (core_halos_back.gd) can call it and always agree, instead
## of one recomputing and the other reading stale/duplicated math. Returns
## {"front": [run, ...], "back": [run, ...]}, each run a Dictionary of
## parallel point/color arrays for the ring's two rim edges, split into
## contiguous runs wherever the ring's rotated Z crosses 0 (the SkillNode's
## own disk sits at the screen plane, so Z>0 is in front of it, Z<0 is
## behind).
##
## Each ring is a HOOP (an uncapped cylinder slice), not a flat washer: the
## band's thickness runs along the ring's OWN spin axis (local Z, offset
## before rotation), not radially in-plane. A radial offset would make every
## ring a flat annulus that reads as a disc with a hole — foreshortening
## into a thin ellipse ring when tilted, never a band with real surface
## facing outward. An axial offset is what makes it a genuine tube wall: at
## rest (face-on) the two rims nearly coincide (a tube seen end-on is just a
## ring), and as the ring tilts you see its actual wall width, the same way
## a real bracelet or a Halo ringworld segment reads.
func _gimbal_runs(base_r: float, halo_color: Color) -> Dictionary:
	var front: Array = []
	var back: Array = []
	var chain := Quaternion.IDENTITY
	for i in gimbal_ring_count:
		var axis: Vector3 = GIMBAL_AXES[i % GIMBAL_AXES.size()]
		# Fixed per-ring phase offset — without it every ring starts spin=0
		# and they're all coincident at rest (and whenever rates line up),
		# so the persistent orthogonal "cage" read needs a standing offset,
		# not just differing spin rates.
		var base_tilt := PI * float(i) / float(gimbal_ring_count)
		var rate := GIMBAL_RATE_BASE * (1.0 + i * 0.4)
		chain = chain * Quaternion(axis, base_tilt + _spin() * rate)
		# Staggered radii (inner/mid/outer), not concentric-but-coincident
		# rings — each successive ring sits further out, same as RINGS.
		var ring_r := base_r * (1.0 + i * GIMBAL_RADIUS_STEP)
		var half_w := ring_r * gimbal_band_width
		var pts_a := PackedVector3Array()  # rim at local Z = -half_w
		var pts_b := PackedVector3Array()  # rim at local Z = +half_w
		pts_a.resize(GIMBAL_SEGMENTS)
		pts_b.resize(GIMBAL_SEGMENTS)
		for s in GIMBAL_SEGMENTS:
			var t := TAU * float(s) / float(GIMBAL_SEGMENTS)
			var rim := Vector2.from_angle(t) * ring_r
			pts_a[s] = chain * Vector3(rim.x, rim.y, -half_w)
			pts_b[s] = chain * Vector3(rim.x, rim.y, half_w)
		_split_ring_runs(pts_a, pts_b, halo_color, front, back)
	return {"front": front, "back": back}


## Walks a ring's sampled points and groups consecutive segments (quads
## between point s and s+1 on the hoop's two rims) by which side of the disk
## plane their average Z falls on. A planar ring generically crosses Z=0 at
## exactly two points per revolution, so this is normally one front run +
## one back run; a near-face-on ring may produce only one (or, at this
## segment resolution, an extra sliver run right at the crossing — harmless,
## just one more draw call). `pts_in`/`pts_out` name which of the hoop's two
## rims each array is (arbitrary since the hoop is symmetric) — not an
## inner/outer radius, that's `_gimbal_runs`' `half_w` offset now.
func _split_ring_runs(pts_in: PackedVector3Array, pts_out: PackedVector3Array, halo_color: Color, front: Array, back: Array) -> void:
	var n := pts_in.size()
	var run_indices: Array = []
	var run_is_front := true
	for s in n:
		var s2 := (s + 1) % n
		var avg_z := (pts_in[s].z + pts_out[s].z + pts_in[s2].z + pts_out[s2].z) * 0.25
		var seg_front := avg_z >= 0.0
		if not run_indices.is_empty() and seg_front != run_is_front:
			var target: Array = front if run_is_front else back
			target.append(_build_run(run_indices, pts_in, pts_out, halo_color))
			run_indices = []
		run_is_front = seg_front
		run_indices.append(s)
	if not run_indices.is_empty():
		var target: Array = front if run_is_front else back
		target.append(_build_run(run_indices, pts_in, pts_out, halo_color))


func _build_run(indices: Array, pts_in: PackedVector3Array, pts_out: PackedVector3Array, halo_color: Color) -> Dictionary:
	var idx: Array = indices.duplicate()
	idx.append((int(indices[-1]) + 1) % pts_in.size())
	var in_pts := PackedVector2Array()
	var in_colors := PackedColorArray()
	var out_pts := PackedVector2Array()
	var out_colors := PackedColorArray()
	for i in idx:
		var p_in: Vector3 = pts_in[i]
		var p_out: Vector3 = pts_out[i]
		in_pts.append(Vector2(p_in.x, p_in.y))
		in_colors.append(_depth_color(halo_color, p_in.z))
		out_pts.append(Vector2(p_out.x, p_out.y))
		out_colors.append(_depth_color(halo_color, p_out.z))
	return {"in_pts": in_pts, "in_colors": in_colors, "out_pts": out_pts, "out_colors": out_colors}


## Depth cue: far side of the band dims, near side stays at full halo_color
## alpha — a per-vertex alpha lerp costs nothing extra (the color array is
## already required for draw_polygon) and sells the 3D read without a shader.
func _depth_color(base: Color, z: float) -> Color:
	var t := clampf((z + 1.0) * 0.5, 0.0, 1.0)
	return Color(base.r, base.g, base.b, lerpf(base.a * 0.35, base.a, t))


## Draws one run's filled band plus a glow stroke on BOTH hoop rims, on
## whichever CanvasItem `target` is — this only works correctly when called
## from INSIDE `target`'s own _draw(), which is why core_halos_back.gd calls
## this itself rather than asking CoreHalos to draw on its behalf (Godot only
## accepts draw_* commands for a CanvasItem while that item is the one
## currently drawing). Fakes the glow via a stacked translucent stroke, same
## CPU technique as rim_bonuses.gd's _draw_glow_arc / rune_ring.gd's edge_glow.
##
## Fills per-SEGMENT quad (draw_primitive, 4 points), not one draw_polygon
## over the whole run: the hoop's two rims are offset along the ring's OWN
## spin axis, not radially, so a heavily tilted ring's projected band can
## fold over itself in 2D — a single ear-clipped polygon over that
## silhouette can fail Godot's triangulator ("Invalid polygon data").
## draw_primitive takes explicit quads, so there's no triangulation to fail;
## each quad between two adjacent samples stays well-formed regardless of
## what the overall run's silhouette looks like.
func _draw_run_on(target: CanvasItem, run: Dictionary, halo_color: Color) -> void:
	var in_pts: PackedVector2Array = run["in_pts"]
	var in_colors: PackedColorArray = run["in_colors"]
	var out_pts: PackedVector2Array = run["out_pts"]
	var out_colors: PackedColorArray = run["out_colors"]
	var count := in_pts.size()
	if count < 2:
		return
	var empty_uvs := PackedVector2Array()
	for i in count - 1:
		var quad_pts := PackedVector2Array([in_pts[i], out_pts[i], out_pts[i + 1], in_pts[i + 1]])
		var quad_colors := PackedColorArray([in_colors[i], out_colors[i], out_colors[i + 1], in_colors[i + 1]])
		target.draw_primitive(quad_pts, quad_colors, empty_uvs)

	target.draw_polyline_colors(in_pts, _glow_colors(in_colors), GIMBAL_GLOW_WIDTH, true)
	target.draw_polyline_colors(out_pts, _glow_colors(out_colors), GIMBAL_GLOW_WIDTH, true)


## Both hoop rims glow — it's a symmetric band, not a one-sided ring.
func _glow_colors(rim_colors: PackedColorArray) -> PackedColorArray:
	var glow_colors := PackedColorArray()
	for c in rim_colors:
		glow_colors.append(Color(c.r, c.g, c.b, c.a * 0.4))
	return glow_colors
