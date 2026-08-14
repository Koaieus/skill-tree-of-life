@tool
class_name Edge
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## Visible edge between two SkillNodes. Regular (non-self-loop) edges own no
## rendering of their own (#413) — they push a transform + a pair of endpoint
## colours into their [Graph]'s shared `edge_mesh` [MultiMeshInstance2D] slot
## (`push_render_state` / `_push_transform` / `_push_colors`), which
## self-shades against the world vision field per-fragment
## (`ui/vision_field.gdshaderinc`) instead of relying on z-order to escape
## `FogOverlay`'s opaque darkness quad. One shared draw call regardless of
## edge count; a camera zoom step touches nothing here at all — width is
## read from `CANVAS_MATRIX` in `graph/edge_mesh.gdshader`'s own vertex().
##
## Self-loops (from == to, no gradient/segment to speak of) are unaffected —
## rare, cheap procedural `_draw()` geometry, kept exactly as before,
## including the old z-index-vs-fog dance (see `sensed`'s setter and
## `ui/fog_overlay/fog_overlay.gd`'s self-loop branch).

signal endpoints_changed

## Packed into the shared MultiMesh's spare alpha channel — see
## `graph/edge_mesh.gdshader`'s header comment. Matches the shader's own
## named constants; keep both in lockstep if either changes.
const VIS_HIDDEN: float = 0.0
const VIS_VISIBLE: float = 1.0
const VIS_SENSED: float = 2.0

## Lit/unlit/sensed are colour TRANSFORMS applied to each endpoint's own
## archetype tint, not fixed overrides — see `_display_color`.
@export_range(0.0, 1.0, 0.05) var unlit_desaturate: float = 0.45
@export_range(0.0, 1.0, 0.05) var unlit_darken: float = 0.15
@export_range(0.0, 1.0, 0.05) var lit_alpha: float = 1.0
@export_range(0.0, 1.0, 0.05) var unlit_alpha: float = 0.75
## Sensed = topology hint only (see `sensed` below). Fixed low alpha so a
## sensed edge in pitch-black doesn't outshine a barely-visible unlit edge
## in someone's vision fade-zone, regardless of lit/unlit archetype colour.
@export_range(0.0, 1.0, 0.05) var sensed_alpha: float = 0.35
## EV stops the lit colour is raised by. Baked directly into the MultiMesh
## instance colours by `_display_color_lifted` (#413 acceptance spec item 3
## — a MultiMesh instance has no per-instance `self_modulate` to carry the
## lift separately the way the old Line2D path did). [constant Emissive.ALERT]
## (the old default) blows every channel of most archetype colours past the
## default `WorldEnvironment`'s hard-clamp tonemapper across the edge's WHOLE
## line body — unlike `rim_ring.gdshader`'s additive ALERT term, which only
## ever lights a thin crest sliver, a lit edge is 100% covered by the lift, so
## it reads as solid white with the endpoint gradient gone (confirmed via a
## real opengl3 screenshot of `dev_bloom_sandbox`, not just the shader math).
## [constant Emissive.VALUE] (2x) still glows visibly brighter than an unlit
## edge without clipping every hue to white.
@export_range(0.0, 6.0, 0.05) var lit_glow_stops: float = Emissive.VALUE

@export var from: SkillNode:
	set(value):
		if from == value:
			return
		_disconnect_endpoint(from)
		from = value
		_connect_endpoint(from)
		_register_self_loop()
		_update_endpoints()
		_update_visual()
		endpoints_changed.emit()

@export var to: SkillNode:
	set(value):
		if to == value:
			return
		_disconnect_endpoint(to)
		to = value
		_connect_endpoint(to)
		_register_self_loop()
		_update_endpoints()
		_update_visual()
		endpoints_changed.emit()

## Self-loop-only now (#413): regular edges' width is a single material
## uniform shared by every edge (`graph/edge_mesh_material.tres`), authored
## once, not per instance. Kept here purely so `_draw_self_loop` has a
## screen-constant width knob, same as before.
@export var width: float = 2.0:
	set(v):
		width = v
		if is_self_loop:
			queue_redraw()

## Last zoom broadcast via [signal Events.camera_zoom_changed]. Only consumed
## by the self-loop `_draw()` path now — regular edges get their
## screen-constant width from `CANVAS_MATRIX` inside the shader itself, no
## CPU zoom hook needed. Stays `1.0` in the editor (`@tool`, no live
## `GraphCamera`) and at runtime before the first camera broadcast.
var _current_zoom: float = 1.0

## Sensed-but-not-clearly-visible: at least one endpoint is sensed
## (not visible). VisionSystem writes this every recompute. When true,
## the edge renders above the fog overlay so the topology hint reads
## through the darkness — a topology breadcrumb, not a full reveal.
## See docs/design/info_gating.md for the broader info dimensions this
## flag will eventually plug into.
##
## Self-loops keep the old z-index-vs-fog dance (see `ui/z_layers.gd`);
## regular edges fold `sensed` into their own MultiMesh colour/vis-state
## push instead (#413) — no z_index write, since self-shading makes the
## z-order-escape trick unnecessary for them.
@export var sensed: bool = false:
	set(value):
		if sensed == value:
			return
		sensed = value
		if is_self_loop:
			# The ABSOLUTE sensed band, not `EDGE + SENSED`. SkillNode gets away
			# with the additive idiom (`skill_node.gd:423`) only because its base
			# band is GRAPH_DEFAULT (0), so 0 + 1001 lands on SENSED. The EDGE
			# band is NEGATIVE, so the same pattern yielded 991 — *below* the
			# opaque FogOverlay quad at ZLayers.FOG (1000), and a sensed
			# self-loop was simply painted over, delivering none of the
			# "topology breadcrumb reads through fog" contract `sensed` exists
			# for. Tradeoff: at 1001 the loop shares its band with a sensed
			# SkillNode and, being later in `graph.tscn`'s child order, now
			# draws OVER the node body instead of sinking under it (see
			# `_draw_self_loop`'s docstring). Reading through fog beats the
			# sunk-ring look; both dissolve once self-loops join the batch.
			z_index = ZLayers.SENSED if sensed else ZLayers.EDGE
		_update_visual()

## Vision-RANGE visibility (distinct from `sensed`'s hops-based sensor
## reach) — written every vision tick by `FogOverlay` for regular edges only
## (self-loops keep the old per-element dimming path). Defaults `true` so a
## scene with no fog system at all (dev sandboxes, most tests) renders at
## full brightness rather than reading the vision field's own "no data"
## default as "hidden". See #413 and `ui/vision_field.gdshaderinc`.
@export var vision_visible: bool = true:
	set(value):
		if vision_visible == value:
			return
		vision_visible = value
		_push_colors()

var is_self_loop: bool:
	get(): return from != null and from == to

## Transform + endpoint colours last computed for the shared MultiMesh slot —
## mirrored here (not just written into the mesh buffer) so a bare
## `add_child_autofree(edge)` test fixture with no live [Graph] parent can
## still assert against them. See test/unit/test_edge_render_state.gd.
var render_transform: Transform2D = Transform2D.IDENTITY
var render_color_a: Color = Color.WHITE
var render_color_b: Color = Color.WHITE
var render_vis_state: float = VIS_VISIBLE

var _render_graph: Graph = null


## Called once by [Graph] right after this edge is added (`edge_added`) —
## gives `_push_transform`/`_push_colors` somewhere to write besides the
## local `render_*` mirrors. A no-op for self-loops (they never get a slot).
func bind_render_target(graph: Graph) -> void:
	_render_graph = graph


## Pushes both transform and colours — called by [Graph] right after it
## registers this edge's slot, since every `from`/`to`-triggered push before
## that point had nowhere to go but the local mirrors.
func push_render_state() -> void:
	_push_transform()
	_push_colors()


func _ready() -> void:
	if not Engine.is_editor_hint():
		_current_zoom = GraphCamera.current_zoom
	Events.camera_zoom_changed.connect(_on_camera_zoom_changed)
	_update_endpoints()
	_update_visual()

func _draw() -> void:
	# Regular edges render through Graph's shared MultiMesh; only self-loops
	# (no straight-line gradient to speak of, from == to) go through _draw.
	if not is_self_loop or from == null:
		return
	_draw_self_loop()

## Lit when both endpoints are owned by the same entity. Override in a
## subclass or replace the predicate later for richer states (e.g. owned
## by anyone vs. owned by the local player).
func is_lit() -> bool:
	return from != null and to != null \
		and from.owned_by != null \
		and from.owned_by == to.owned_by

## Recomputes rendering from current endpoint positions. Call after moving an
## endpoint node directly (bypassing the `from`/`to` setters) — e.g. a
## sandbox/playground layout pass — since Edge only listens for owner/radius/
## archetype changes, not position, and would otherwise keep rendering the
## segment at the endpoints' positions as of connect-time.
func refresh_endpoints() -> void:
	_update_endpoints()
	queue_redraw()

func _update_endpoints() -> void:
	if is_self_loop:
		queue_redraw()
		return
	_push_transform()

## Recomputes what should be pushed to the shared MultiMesh slot — endpoint
## colours + vision-state for regular edges, or just a redraw for self-loops
## (colour is resolved fresh in `_draw_self_loop`). Cheap enough to fully
## recompute rather than diff.
func _update_visual() -> void:
	if is_self_loop:
		queue_redraw()
		return
	_push_colors()

## World-space segment between `from`/`to`, converted into the shared
## MultiMesh's local space (== Graph's own space, since Edge/edges_container/
## edge_mesh are all unpositioned siblings under Graph — same simplifying
## assumption the old Line2D path made subtracting `global_position`) and
## pushed as a quad transform: origin at the segment midpoint, x-axis along
## the segment scaled to its length, unit y-axis (width is NOT baked in here
## — the shader expands it from a material uniform at draw time, see
## `graph/edge_mesh.gdshader`).
func _push_transform() -> void:
	if is_self_loop or from == null or to == null:
		return
	var seg := SkillNode.segment_between(from, to)
	if seg.is_empty():
		return
	var origin_offset := _render_graph.global_position if _render_graph != null else Vector2.ZERO
	var a: Vector2 = seg[0] - origin_offset
	var b: Vector2 = seg[1] - origin_offset
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var xf := Transform2D((b - a).angle(), mid)
	xf.x *= length
	render_transform = xf
	if _render_graph != null:
		_render_graph.set_edge_transform(self, xf)

## Recomputes endpoint colours + vision-state and pushes them to the shared
## MultiMesh slot (or just the local mirrors, with no live Graph — see
## `render_color_a`/`render_color_b`'s docstring).
func _push_colors() -> void:
	if is_self_loop or from == null or to == null:
		return
	var lit := is_lit()
	render_color_a = _display_color_lifted(from.base_type_color, lit)
	render_color_b = _display_color_lifted(to.base_type_color, lit)
	render_vis_state = VIS_SENSED if sensed else (VIS_VISIBLE if vision_visible else VIS_HIDDEN)
	if _render_graph != null:
		_render_graph.set_edge_colors(self, render_color_a, render_color_b, render_vis_state)

## World-space line width that renders at a constant `width` SCREEN pixels
## regardless of camera zoom — self-loop `_draw_self_loop` only now; regular
## edges get this from `CANVAS_MATRIX` inside the shader instead (#413).
func _screen_constant_width() -> float:
	return width / _current_zoom

func _on_camera_zoom_changed(zoom: float) -> void:
	_current_zoom = zoom
	if is_self_loop:
		queue_redraw()

## Archetype tint → rendered colour, SDR only. Lit desaturates toward white
## less (kept ~full alpha), unlit desaturates toward its own luminance grey
## and darkens; sensed forces the unlit treatment regardless of actual lit
## state — owner identity sits above the topology gate, so a sensed-but-
## co-owned edge must not leak "lit" through fog — then caps alpha on top at
## a fixed low floor.
##
## Used by the self-loop `_draw()` path (which has no per-instance HDR
## channel the way the MultiMesh path does) — see `_display_color_lifted`
## for the regular-edge variant that additionally bakes in the emissive lift.
func _display_color(base: Color, lit: bool) -> Color:
	var c := base
	var effective_lit := lit and not sensed
	if effective_lit:
		c.a = lit_alpha
	else:
		var gray := c.get_luminance()
		c = c.lerp(Color(gray, gray, gray, c.a), unlit_desaturate)
		c = c.darkened(unlit_darken)
		c.a = unlit_alpha
	if sensed:
		c.a = sensed_alpha
	return c

## Multimesh-path colour: bakes the HDR emissive lift directly into rgb since
## a MultiMesh instance has no per-instance `self_modulate` to carry it
## separately (#413 acceptance spec item 3). `_display_color` stays SDR-only
## for the self-loop `_draw()` path, unaffected by this issue.
##
## Deliberately NOT `Emissive.at()` — that helper's final `.linear_to_srgb()`
## re-encode exists so a `source_color`-hinted SHADER UNIFORM (e.g. rim_ring's
## `ring_tint`) round-trips byte-identical to the ColorPicker: GDScript encodes
## to sRGB, the engine auto-decodes it back to linear on upload because of the
## `source_color` hint, and the shader ends up with the correct linear value.
## `MultiMesh.set_instance_color`/`set_instance_custom_data` carry no such
## hint — Godot uploads them as raw numbers and `graph/edge_mesh.gdshader`
## reads them straight into `COLOR`/`INSTANCE_CUSTOM`, no auto-decode. Calling
## `Emissive.at()` here re-encoded a value nothing downstream ever decoded
## back — sRGB's gamma curve is sub-linear even past 1.0, so each stop's
## intended linear overshoot got compressed before it ever reached the glow
## pass, and `glow_hdr_threshold`'s 1.0 cutoff barely triggered regardless of
## `lit_glow_stops` (confirmed empirically: stops up to 6.0 produced no
## visible bloom at the project's default `glow_intensity`). Multiplying the
## raw sRGB-numeric base directly by `pow(2, stops)` — same convention
## `rim_ring.gdshader` uses on its already-linear-decoded `ring_tint`, just
## without a decode step this path never had to begin with — hands the glow
## pass the actual intended overshoot.
##
## The boost is applied relative to the colour's OWN gray floor
## (`minf(r,g,b)`), not to the raw channels — scaling all three channels by
## the same flat factor keeps their ratio constant, so at high stops the
## WEAK channels cross the display's clip threshold right alongside the
## dominant one and the whole line reads as solid white, hue gone (this is
## why raising `lit_glow_stops` alone couldn't fix the earlier white-edges
## bug — same failure mode as the flat-multiply version, just a different
## cause). Leaving the floor unboosted and multiplying only the channel's
## rise above it means only the dominant channel(s) blow past 1.0 while the
## weak ones stay put — the core reads as saturated red/gold instead of
## white, and only the very brightest pixels (where even the floor was
## already high) go full white-hot, same as a real lightsaber/molten-metal
## look.
##
## The floor itself still gets a SMALL, fixed lift ([constant Emissive.VALUE],
## not the user-tunable `lit_glow_stops`) — an achromatic base (`r == g == b`,
## e.g. the default unallocated `Color.DIM_GRAY`) has zero chroma to boost, so
## without this a gray lit edge would render pixel-identical to its unlit
## sibling no matter how high `lit_glow_stops` goes. Capping the floor's own
## boost independent of the chroma boost keeps gray edges visibly "on" without
## ever blowing them white the way lifting the whole floor by the full
## user-tunable factor would.
func _display_color_lifted(base: Color, lit: bool) -> Color:
	var c := _display_color(base, lit)
	if lit and not sensed:
		var chroma_boost := pow(2.0, lit_glow_stops)
		var floor_boost := pow(2.0, Emissive.VALUE)
		var floor_v: float = minf(c.r, minf(c.g, c.b))
		var lifted_floor := floor_v * floor_boost
		c = Color(
			lifted_floor + (c.r - floor_v) * chroma_boost,
			lifted_floor + (c.g - floor_v) * chroma_boost,
			lifted_floor + (c.b - floor_v) * chroma_boost,
			c.a,
		)
	return c

## Self-loop glyph: a circular ring sunk slightly into the node so its near
## tangent point sits *under* the node body instead of kissing the rim from
## outside — the edge sits on the absolute ZLayers.EDGE band, below the
## graph-default band SkillNode draws on, so the overlapped arc is occluded
## and the ring reads as emerging from / vanishing into the node rather than
## floating next to it as a separate lollipop.
##
## CAVEAT: that occlusion holds only while the loop is UNSENSED. A sensed
## self-loop is promoted to the absolute ZLayers.SENSED band (see the `sensed`
## setter) so it can clear the fog quad at ZLayers.FOG, which puts it level
## with the sensed SkillNode and later in `graph.tscn`'s child order — so it
## draws OVER the node body and the sunk read is lost for exactly that state.
## Deliberate: a breadcrumb nobody can see through the fog is worth less than
## a correctly-sunk ring. Both go away once self-loops join the edge batch.
##
## Direction is the bisector of the LARGEST angular gap between the node's
## other edges — keeps the self-loop visually clear of existing edges
## without disturbing them. Falls back to 12 o'clock when the node has no
## other edges. Multiple self-loops on the same node share that direction
## but nest at growing radii (indexed via `from.self_loops`) so they read
## as concentric rings instead of stacking on top of each other.
## Recomputed each draw (cheap; degree ≪ 16 in practice).
const SELF_LOOP_SINK: float = 4.0

func _draw_self_loop() -> void:
	var node_center := from.global_position - global_position
	var r: float = from.radius
	var idx: int = max(from.self_loops.find(self), 0)
	var loop_radius: float = r * 0.55 * (1.0 + idx * 0.4)
	var angle := _self_loop_bisector_angle()
	var loop_center := node_center + Vector2.from_angle(angle) * (r + loop_radius - SELF_LOOP_SINK)
	var lit := is_lit()
	# `_display_color_lifted`, not `_display_color`: the latter is SDR-only by
	# its own docstring, and it was the exact reason a lit self-loop never
	# glowed while every lit regular edge touching the same node did. The lift
	# is the ONLY place `pow(2, lit_glow_stops)` is applied, so the authored
	# `lit_glow_stops = 4.5` was silently a no-op for self-loops and their
	# colour never crossed the WorldEnvironment's 1.0 glow threshold.
	#
	# The raw (non-`Emissive.at()`) multiply is right here for the same reason
	# it is right on the multimesh path: `draw_arc`'s Color carries no
	# `source_color` hint, so nothing downstream decodes an sRGB re-encode —
	# see `_display_color_lifted`'s docstring for the full derivation.
	var c := _display_color_lifted(from.base_type_color, lit)
	var w := _screen_constant_width()
	draw_arc(loop_center, loop_radius, 0.0, TAU, 24, c, w, false)


## Registers `self` into `from.self_loops` the moment both endpoints make
## this edge a self-loop — idempotent, and independent of whoever built the
## edge (Graph.add_edge already does this for runtime/procgen edges, but a
## scene-authored self-loop sets `from`/`to` straight through these setters
## and would otherwise never register). Without this, `_draw_self_loop`'s
## `self_loops.find(self)` returns -1 for every scene-baked self-loop, so
## they'd all nest at the same radius instead of spreading.
func _register_self_loop() -> void:
	if not is_self_loop:
		return
	if not from.self_loops.has(self):
		from.self_loops.append(self)


## Returns the direction (radians) the self-loop should sit in: the
## midpoint of the widest gap between `from`'s other outgoing edges.
## -PI/2 (12 o'clock) when the node has no other edges.
func _self_loop_bisector_angle() -> float:
	if from == null or get_parent() == null:
		return -PI / 2.0
	var node_pos := from.global_position
	var angles: PackedFloat32Array = []
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is Edge):
			continue
		var other := _other_endpoint(sibling as Edge)
		if other == null:
			continue
		angles.append((other.global_position - node_pos).angle())
	if angles.is_empty():
		return -PI / 2.0
	angles.sort()
	# Widest gap (with wrap-around): place the loop in its bisector.
	var best_gap: float = -1.0
	var best_angle: float = -PI / 2.0
	for i in angles.size():
		var a1: float = angles[i]
		var a2: float = angles[(i + 1) % angles.size()]
		var gap: float = a2 - a1
		if i == angles.size() - 1:
			gap += TAU  # wrap-around closes the circle
		if gap > best_gap:
			best_gap = gap
			best_angle = a1 + gap * 0.5
	return best_angle


## Returns the endpoint of `e` that is NOT `from` — used by self-loop angle
## computation to gather the directions of all other edges incident to
## `from`. Returns null when `e` doesn't touch `from` or is itself a
## self-loop on `from` (those don't contribute a direction).
func _other_endpoint(e: Edge) -> SkillNode:
	if e.from == from and e.to != from:
		return e.to
	if e.to == from and e.from != from:
		return e.from
	return null


func _connect_endpoint(node: SkillNode) -> void:
	if node == null:
		return
	if not node.owner_changed.is_connected(_on_endpoint_owner_changed):
		node.owner_changed.connect(_on_endpoint_owner_changed)
	if not node.radius_changed.is_connected(_on_endpoint_radius_changed):
		node.radius_changed.connect(_on_endpoint_radius_changed)
	if not node.archetype_changed.is_connected(_on_endpoint_archetype_changed):
		node.archetype_changed.connect(_on_endpoint_archetype_changed)


func _disconnect_endpoint(node: SkillNode) -> void:
	if node == null:
		return
	if node.owner_changed.is_connected(_on_endpoint_owner_changed):
		node.owner_changed.disconnect(_on_endpoint_owner_changed)
	if node.radius_changed.is_connected(_on_endpoint_radius_changed):
		node.radius_changed.disconnect(_on_endpoint_radius_changed)
	if node.archetype_changed.is_connected(_on_endpoint_archetype_changed):
		node.archetype_changed.disconnect(_on_endpoint_archetype_changed)


func _on_endpoint_owner_changed() -> void:
	_update_visual()

func _on_endpoint_radius_changed() -> void:
	_update_endpoints()
	queue_redraw()

func _on_endpoint_archetype_changed() -> void:
	_update_visual()
