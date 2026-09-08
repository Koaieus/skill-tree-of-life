@tool
extends SkillNodeVisual
## Core presence halos (#128): concentric halo marks scaled for "this is a
## nucleus" presence. Spikes are explicitly excluded — that mark is
## reserved for the addons system (fortify/plates), not core identity.
##
## Reads [member SkillNodeVisual.entity_tint]: a core marks "this is YOUR
## nucleus", so it carries ownership, not archetype. Only the halo's own
## translucency is private ([member halo_opacity]).

enum CoreHaloStyle { NONE, RINGS, ORBIT, GIMBAL, COG }

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

@export var halo_style: CoreHaloStyle = CoreHaloStyle.NONE:
	set(value):
		halo_style = value
		_rebuild_spin_layers()
		_refresh_animation()
		_redraw_all()

## Whether this node is out of the fog for the local viewer — pushed down from
## [member SkillNode.revealed] via [method NodeVisualsComposite.set_core_halo_revealed]
## (#802). Half of the animation gate below; the other half is on-screen.
var halo_revealed: bool = true:
	set(value):
		if halo_revealed == value:
			return
		halo_revealed = value
		_refresh_animation()

## Scales the halo radius outward from the rim.
@export_range(1.0, 2.0, 0.01) var halo_scale: float = 1.3:
	set(value):
		halo_scale = value
		_resize_notifier()
		_redraw_all()

@export_range(0.5, 3.0, 0.01) var spin_speed: float = 1.0

## GIMBAL only: how many nested rings the gyroscope has. The owner asked for
## this to be tunable ("a real gyroscope with N spin axis").
@export_range(2, 5, 1) var gimbal_ring_count: int = 3:
	set(value):
		gimbal_ring_count = value
		_resize_notifier()
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

## Rigid-geometry layers for the non-GIMBAL styles (#802) — one CanvasItem per
## independently-spinning ring, drawn once and animated by `rotation`. Empty for
## NONE and for GIMBAL (whose projected silhouette genuinely changes every
## frame, so it cannot be a 2D transform).
var _spin_layers: Array[Node2D] = []

## Exported setters run while the scene is still being instantiated (before
## this node has entered the tree), and rebuilding the layer children then only
## to rebuild them again at READY is pure churn — so the rebuild is deferred to
## READY and every later style change does it for real.
var _ready_done: bool = false

## Last colour the layers were painted with — see [method _on_identity_changed]
## for why this component needs an idempotence guard the redraw-every-frame
## version did not. Alpha < 0 is an impossible [Color], so the first identity
## write always lands.
var _painted_color: Color = Color(0.0, 0.0, 0.0, -1.0)

## Set by [VisibleOnScreenNotifier2D] below. Starts false: the notifier emits
## `screen_entered` on its first served frame when it IS on screen, so the
## honest default is "assume not, let the server say otherwise" — a fail-OPEN
## default would leave every off-screen halo animating forever, which is the
## bug (#802).
var _on_screen: bool = false
var _notifier: VisibleOnScreenNotifier2D = null

## Frame stamp + memo for [method gimbal_layer_batch]: the front and back halves
## share ONE computation per frame instead of each running the full
## compose -> transform -> project -> depth-split and discarding the other half.
var _gimbal_frame: int = -1
var _gimbal_front: Dictionary = {}
var _gimbal_back: Dictionary = {}

const SPIN_LAYER_SCENE: PackedScene = preload("res://skill_node/visuals/halo_spin_layer.tscn")
const GIMBAL_SEGMENTS := 28
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


## One tick of the shared clock ([method SkillNodeVisual._on_anim_tick]).
##
## For the rotate-able styles this is the whole point of #802: write each
## layer's `rotation` and DON'T queue a redraw — Godot keeps the geometry it
## already has, so an animating COG costs a float write instead of a rebuilt
## circle + ten teeth.
##
## GIMBAL still rebuilds, and still has to drive its back layer explicitly:
## the base class's clock only redraws the node it is declared on, so without
## this the far arcs freeze mid-spin while the front half keeps animating.
func _on_anim_tick() -> void:
	if not _spin_layers.is_empty():
		_apply_spin_rotations()
		return
	queue_redraw()
	if halo_style == CoreHaloStyle.GIMBAL and is_instance_valid(_back_layer):
		_back_layer.queue_redraw()


## A full invalidation: everything this component has cached or already drawn is
## thrown away. Called whenever an INPUT changes (style, radius, scale, tint,
## opacity) rather than every frame — the spin layers hold baked geometry, so
## they only redraw here.
func _redraw_all() -> void:
	_gimbal_frame = -1
	queue_redraw()
	for layer in _spin_layers:
		if is_instance_valid(layer):
			layer.queue_redraw()
	if halo_style == CoreHaloStyle.GIMBAL and is_instance_valid(_back_layer):
		_back_layer.queue_redraw()


## Identity and radius both feed BAKED geometry now, so the base class's plain
## `queue_redraw()` is no longer enough — the spin layers own their own canvas
## items and would keep the old colour/size.
##
## Both channels are therefore also made IDEMPOTENT, which the redraw-every-frame
## version never needed: the composite loop-sets all three identity values into
## every child on any one of them changing, and `SkillNode._sync_visuals()`
## re-pushes `configure(radius)` wholesale. Neither runs per frame today, but an
## unguarded repaint here would silently undo #802 the day one of them did —
## the whole win is that these layers are painted once.
##
## `_halo_color` is the ONLY identity this component draws with (it reads
## `entity_tint` and its own `halo_opacity`; `archetype_tint` and `allocated`
## are not its business), so comparing it is exact, not a heuristic.
func _on_identity_changed() -> void:
	var color := _halo_color
	if color == _painted_color:
		return
	_painted_color = color
	_redraw_all()


func configure(new_radius: float) -> void:
	if is_equal_approx(new_radius, radius):
		return
	super(new_radius)
	_resize_notifier()
	_redraw_all()


## Wires the gate up on ready and re-evaluates it whenever this node's
## visibility-in-tree changes (the composite hides the whole [CorePresence]
## for a non-core node and the whole ShaderStack for a sensed one).
##
## `super._notification` first — the base uses NOTIFICATION_READY to re-assert
## the process flag, and `_refresh_animation` is what decides its real value.
func _notification(what: int) -> void:
	super._notification(what)
	match what:
		NOTIFICATION_READY:
			_ready_done = true
			_rebuild_spin_layers()
			_refresh_animation()
		NOTIFICATION_VISIBILITY_CHANGED:
			_refresh_animation()


## The animation gate (#802). `set_animating(halo_style != NONE)` keyed off
## WHAT the halo is and never off whether anyone can see it — so 307 cores on a
## 2000-node board rebuilt their geometry every frame with exactly one of them
## on screen, and a fully-fogged node (neither `sensed` nor `revealed`, so the
## ShaderStack hide never fires) kept animating underneath the fog overlay.
##
## Animate iff the item is actually in the tree AND someone could see it. The
## on-screen half is deliberately OR'd rather than AND'ed with `revealed`: the
## notifier is the engine's answer and can be silent (headless, a fresh frame),
## and `revealed` alone is the safe fallback.
func _refresh_animation() -> void:
	var live := halo_style != CoreHaloStyle.NONE and is_visible_in_tree()
	_sync_notifier(live)
	set_animating(live and (halo_revealed or _on_screen))


## The on-screen half of the gate, from the engine rather than a per-frame
## rect test in GDScript. Created LAZILY and only while the halo could animate
## at all: `core_presence.tscn` authors GIMBAL onto every SkillNode's CoreHalos,
## ~1700 of which are non-core and hidden, and a notifier on each of those would
## be exactly the always-instanced dead child that #172/#238 retired.
func _sync_notifier(wanted: bool) -> void:
	if wanted == (_notifier != null):
		return
	if wanted:
		_notifier = VisibleOnScreenNotifier2D.new()
		_notifier.screen_entered.connect(_on_screen_changed.bind(true))
		_notifier.screen_exited.connect(_on_screen_changed.bind(false))
		add_child(_notifier)
		_resize_notifier()
	else:
		_notifier.queue_free()
		_notifier = null
		_on_screen = false


func _on_screen_changed(value: bool) -> void:
	_on_screen = value
	_refresh_animation()


## The notifier's rect has to cover the WIDEST style this component can draw —
## GIMBAL's outermost ring — or a halo would stop animating slightly before it
## leaves the screen.
func _resize_notifier() -> void:
	if _notifier == null:
		return
	var r := radius * halo_scale * (1.0 + float(gimbal_ring_count - 1) * GIMBAL_RADIUS_STEP)
	_notifier.rect = Rect2(-r, -r, r * 2.0, r * 2.0)


## Rebuilds the rigid spin layers for the current style. Each entry is one
## independently-rotating CanvasItem: RINGS gets three (its rings run at 1.0 /
## 1.5 / 2.0), ORBIT and COG one each, GIMBAL and NONE none.
##
## The rates are the SAME numbers the old `_draw_*` methods baked into their
## angles — a rotation by `offset` and a redraw with every angle shifted by
## `offset` are the same picture, which is exactly why this substitution is
## sound for these three styles and not for GIMBAL.
func _rebuild_spin_layers() -> void:
	if not _ready_done:
		return
	for layer in _spin_layers:
		if is_instance_valid(layer):
			layer.queue_free()
	_spin_layers.clear()
	for spec in _spin_layer_rates():
		var layer: Node2D = SPIN_LAYER_SCENE.instantiate()
		layer.layer_index = _spin_layers.size()
		layer.spin_rate = spec
		add_child(layer)
		_spin_layers.append(layer)
	_apply_spin_rotations()


func _spin_layer_rates() -> PackedFloat32Array:
	match halo_style:
		CoreHaloStyle.RINGS:
			return PackedFloat32Array([1.0, 1.5, 2.0])
		CoreHaloStyle.ORBIT:
			return PackedFloat32Array([1.0])
		CoreHaloStyle.COG:
			return PackedFloat32Array([0.3])
		_:
			return PackedFloat32Array()


func _apply_spin_rotations() -> void:
	var spin := _spin()
	for layer in _spin_layers:
		layer.rotation = spin * layer.spin_rate


## Whether GIMBAL is the active preset — the back layer checks this via duck
## typing (it doesn't statically type its parent as CoreHalos) so this class
## doesn't need a `class_name`, matching every other leaf component in this
## family.
## CorePresence travel hook (#128, docs/domain/skillnode-emblem.md): the halo
## physically glides — offset in from `local_offset`, tween back to
## Vector2.ZERO. See core_presence.gd for the duck-typed contract.
func on_core_travel_start(local_offset: Vector2, duration: float) -> void:
	position = local_offset
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2.ZERO, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func is_gimbal_active() -> bool:
	return halo_style == CoreHaloStyle.GIMBAL


## This node's OWN canvas item now draws the GIMBAL front half and nothing
## else — every other style lives on its own [HaloSpinLayer] child, which is
## what lets it be rotated instead of rebuilt (#802).
func _draw() -> void:
	if halo_style != CoreHaloStyle.GIMBAL:
		return
	_draw_batch(self, gimbal_layer_batch(true))


## Paints ONE rigid spin layer, in its own un-rotated frame — the layer's
## `rotation` supplies the angle the old `_draw_*` methods baked into every
## vertex. Called from [HaloSpinLayer._draw] (duck-typed, like
## core_halos_back.gd) so all the style knowledge stays here.
func paint_spin_layer(target: CanvasItem, index: int) -> void:
	var halo_color := _halo_color
	var base_r := radius * halo_scale
	match halo_style:
		CoreHaloStyle.RINGS:
			_paint_dashed_circle(target, base_r * (1.0 + index * 0.18), 10, halo_color)
		CoreHaloStyle.ORBIT:
			_paint_orbit(target, base_r, halo_color)
		CoreHaloStyle.COG:
			_paint_cog(target, base_r, halo_color)


func _paint_orbit(target: CanvasItem, base_r: float, halo_color: Color) -> void:
	target.draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	# The orbiting dots read as solid beads on a translucent track.
	var dot_color := Color(halo_color, 1.0)
	var dot_count := 4
	for i in dot_count:
		target.draw_circle(polar_point(base_r, (TAU / dot_count) * i), 2.5, dot_color)


## Real gyroscope, not a faked tilt: each ring is a hoop (uncapped cylinder
## slice) at its own staggered radius; ring i's orientation is ring (i-1)'s
## orientation composed with ring i's own local spin (a quaternion chain), so
## the outer ring spins independently and every inner ring's pivot is
## mounted on the one outside it — the literal mechanism of a gimbal, not a
## phase offset.
## See _gimbal_runs()/_draw_run_on() for the shared geometry this and
## core_halos_back.gd (the "passes behind the disk" layer) both draw from.
## The ONE gimbal computation for this frame, shared by both halves (#802).
##
## `_gimbal_runs()` was previously run TWICE per frame per gimbal: this node
## computed every ring in full and kept only `runs["front"]`, while
## core_halos_back.gd re-ran the identical compose -> transform -> project ->
## depth-split and kept only `runs["back"]`. Each discarded half of a full
## computation, doubling the dominant term. Memoising on the process-frame
## counter keeps the invariant that made the duplication deliberate in the
## first place — the two halves cannot drift into disagreeing geometry —
## and makes it stronger: they are now literally the same computation, not two
## that happen to agree. [method _redraw_all] invalidates the stamp, so an
## input that changes mid-frame is still picked up.
func gimbal_layer_batch(front: bool) -> Dictionary:
	var frame := Engine.get_process_frames()
	if _gimbal_frame != frame:
		_gimbal_frame = frame
		var runs := _gimbal_runs(radius * halo_scale, _halo_color)
		_gimbal_front = _gimbal_batch(runs["front"])
		_gimbal_back = _gimbal_batch(runs["back"])
	return _gimbal_front if front else _gimbal_back


func _paint_cog(target: CanvasItem, base_r: float, halo_color: Color) -> void:
	target.draw_circle(Vector2.ZERO, base_r, halo_color, false, 1.0)
	var teeth := 10
	var tooth_len := base_r * 0.12
	for i in teeth:
		var theta := (TAU / teeth) * i
		target.draw_line(polar_point(base_r, theta), polar_point(base_r + tooth_len, theta), halo_color, 2.0, true)


func _paint_dashed_circle(target: CanvasItem, r: float, dash_count: int, color: Color) -> void:
	var step := TAU / dash_count
	for i in dash_count:
		var a0 := i * step
		target.draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, color, 1.5, true)


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


## Draws a whole layer's runs (front OR back) in ONE draw call — the #239 perf
## fix. `target` is whichever CanvasItem is currently drawing (this node for the
## front half, core_halos_back.gd for the back half), and this only works
## correctly when called from INSIDE `target`'s own _draw() — which is why
## core_halos_back.gd calls it itself rather than asking CoreHalos to draw on
## its behalf (Godot only accepts draw_* / canvas_item_add_* for a CanvasItem
## while that item is the one currently drawing).
##
## `canvas_item_add_triangle_array` submits the entire pre-triangulated buffer
## (band fills + both glow strips, for every ring's runs) as a single command,
## replacing the old ~384-call-per-gimbal loop of per-segment `draw_primitive`s
## plus two `draw_polyline_colors` per run. See _gimbal_batch for why we can
## fold everything into one buffer safely.
func _draw_batch(target: CanvasItem, batch: Dictionary) -> void:
	var points: PackedVector2Array = batch["points"]
	if points.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		target.get_canvas_item(), batch["indices"], points, batch["colors"])


## Builds one flat, pre-triangulated vertex/color/index buffer for a layer's
## runs. We supply our OWN 2-tris-per-quad indices, so Godot's ear-clipping
## triangulator never runs — which is what made the old per-segment
## `draw_primitive` necessary: the hoop's two rims are offset along the ring's
## own spin axis (not radially), so a heavily tilted ring's projected band can
## fold over itself in 2D, and a single ear-clipped `draw_polygon` over that
## silhouette could fail ("Invalid polygon data"). Explicit indices sidestep
## triangulation entirely, so the fold is moot and the whole layer collapses
## into one `canvas_item_add_triangle_array` call (see _draw_batch).
func _gimbal_batch(runs: Array) -> Dictionary:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for run in runs:
		_append_run(run, points, colors, indices)
	return {"points": points, "colors": colors, "indices": indices}


## Appends one run's band fill (a quad per segment between the two rims) plus a
## glow strip along BOTH rims into the shared buffer. The glow — a faked bloom,
## same CPU technique as rim_bonuses.gd / rune_ring.gd — is folded in as thin
## quads rather than a separate `draw_polyline_colors`, so it costs zero extra
## draw calls (the polylines would otherwise dominate once the fills batch, see
## #239).
func _append_run(run: Dictionary, points: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var in_pts: PackedVector2Array = run["in_pts"]
	var in_colors: PackedColorArray = run["in_colors"]
	var out_pts: PackedVector2Array = run["out_pts"]
	var out_colors: PackedColorArray = run["out_colors"]
	var count := in_pts.size()
	if count < 2:
		return
	for i in count - 1:
		_append_quad(points, colors, indices,
			in_pts[i], out_pts[i], out_pts[i + 1], in_pts[i + 1],
			in_colors[i], out_colors[i], out_colors[i + 1], in_colors[i + 1])
	_append_glow_strip(points, colors, indices, in_pts, _glow_colors(in_colors))
	_append_glow_strip(points, colors, indices, out_pts, _glow_colors(out_colors))


## One quad = two triangles (0-1-2, 0-2-3), indices supplied so no triangulator
## runs. Canvas items don't backface-cull, so winding order is irrelevant.
func _append_quad(points: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array,
		p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	var base := points.size()
	points.push_back(p0)
	points.push_back(p1)
	points.push_back(p2)
	points.push_back(p3)
	colors.push_back(c0)
	colors.push_back(c1)
	colors.push_back(c2)
	colors.push_back(c3)
	indices.push_back(base)
	indices.push_back(base + 1)
	indices.push_back(base + 2)
	indices.push_back(base)
	indices.push_back(base + 2)
	indices.push_back(base + 3)


## A GIMBAL_GLOW_WIDTH-wide strip of quads tracing a rim polyline — the
## triangle-buffer equivalent of the old `draw_polyline_colors` glow stroke.
## Miterless (no corner join) — at this on-screen size with a translucent glow
## the tiny gaps/overlaps at joints are invisible.
func _append_glow_strip(points: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array,
		rim: PackedVector2Array, glow: PackedColorArray) -> void:
	var count := rim.size()
	var half_w := GIMBAL_GLOW_WIDTH * 0.5
	for i in count - 1:
		var a := rim[i]
		var b := rim[i + 1]
		var dir := b - a
		if dir.length_squared() < 0.0001:
			continue
		var n := dir.orthogonal().normalized() * half_w
		_append_quad(points, colors, indices,
			a - n, a + n, b + n, b - n,
			glow[i], glow[i], glow[i + 1], glow[i + 1])


## Both hoop rims glow — it's a symmetric band, not a one-sided ring.
func _glow_colors(rim_colors: PackedColorArray) -> PackedColorArray:
	var glow_colors := PackedColorArray()
	for c in rim_colors:
		glow_colors.append(Color(c.r, c.g, c.b, c.a * 0.4))
	return glow_colors
