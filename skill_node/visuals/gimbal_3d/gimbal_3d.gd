@tool
extends Node3D
## Real-3D core-halo gimbal (#239). The 2D CoreHalos GIMBAL fakes a gyroscope by
## quaternion-rotating hoop points and orthographically projecting them; this is
## the same quaternion chain driving actual [TorusMesh] rings in a [SubViewport]
## world, so the over/under interleave is a depth buffer (not a hand-split
## front/back CanvasItem) and the neon/glass/glyph looks are shader emissives lit
## by a real glow [Environment] — the "techy/sharp/neon/pcb/glass-holo/arcane"
## register the CPU stacked-stroke fake can't reach.
##
## Shares the CoreHalos contract by intent: it consumes an identity [member tint]
## (entity ownership, same as CoreHalos reads entity_tint) + drive params
## (ring count, spin), and the look is one [enum Style] swap — so boss tiers can
## dial epic-ness up the same way a 2D halo_style would. Not yet wired into the
## live SkillNode pipeline; previewed via the sandbox "Gimbal 3D" tab and
## gimbal_3d_showcase.tscn.

## The three showcase looks. UNIFORM_GLOW is the 3D echo of the 2D halo (evenly
## emissive); HOLO_GLASS is semitransparent with fresnel-lit glowing edges;
## SOLID_GLYPH is an opaque metal hoop inscribed with glowing runes on its
## inward-facing surface (the "WILD machinery" the 2D path flagged as out of
## scope — a torus has real UVs, so it's a scrolling emissive here).
enum Style { UNIFORM_GLOW, HOLO_GLASS, SOLID_GLYPH }

@export var style: Style = Style.UNIFORM_GLOW:
	set(value):
		style = value
		_rebuild()

@export_range(1, 5, 1) var ring_count: int = 3:
	set(value):
		ring_count = value
		_rebuild()

## Identity color — ownership, mirroring CoreHalos' read of entity_tint.
@export var tint: Color = Color(0.36, 0.9, 0.585):
	set(value):
		tint = value
		_apply_tint()

@export_range(0.5, 3.0, 0.01) var spin_speed: float = 1.0

## Radius of the innermost ring, in the SubViewport world's units.
@export_range(0.3, 3.0, 0.01) var base_radius: float = 1.0:
	set(value):
		base_radius = value
		_rebuild()

## Each band's axial width as a fraction of its own radius — how tall the
## band reads (the 3D twin of CoreHalos.gimbal_band_width).
@export_range(0.03, 0.45, 0.01) var band_width: float = 0.22:
	set(value):
		band_width = value
		_rebuild()

## Radial thickness of the band as a fraction of its radius — a NUDGE of depth so
## the hoop reads as a solid ring (outer wall + inner wall + two rims) rather than
## a zero-thickness cylinder slice. Tweakable independently of [member band_width]
## (axial). 0 collapses back to the thin single wall. The SOLID_GLYPH inscription
## lives on the inner wall and the rims stay bare — see gimbal_glyph.gdshader.
@export_range(0.0, 0.4, 0.005) var thickness: float = 0.06:
	set(value):
		thickness = value
		_rebuild()

## Sides around each band. Low = angular/faceted (techy/PCB read); high = smooth.
@export_range(6, 48, 1) var facets: int = 24:
	set(value):
		facets = value
		_rebuild()

# The quaternion chain (axes + rates + standing tilts) is the "same gimbal" the
# 2D CoreHalos GIMBAL uses; the radius layout is substrate-specific (thin 3D
# bands need more separation than the 2D hoops).
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.RIGHT, Vector3.UP, Vector3.RIGHT]
const RATE_BASE := 0.35
const RADIUS_STEP := 0.34
# CylinderMesh's wall runs around its Y axis; rotate it so the axis is the ring's
# own normal (local Z), i.e. the band lies in the ring plane like the 2D hoop.
const MESH_CORR := Basis(Vector3(1, 0, 0), PI * 0.5)

# One shared ShaderMaterial per style (tint is an instance uniform, so every
# ring/rig still batches) — same "shared material, vary by instance uniform"
# discipline as inner_disk/rim_ring. Lazily built, cached across all rigs.
static var _mats: Dictionary = {}
static var _glyph_tex: ImageTexture

var _t := 0.0
var _rings: Array[MeshInstance3D] = []


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if _rings.is_empty():
		return
	_t += delta * spin_speed
	# The gimbal chain: chain index 0 is the OUTERMOST ring (the base/parent);
	# each successive inner ring composes its own spin ONTO the accumulated outer
	# rotation, so spinning an outer ring bodily carries every ring inside it —
	# the literal mechanism (see skill-node-visuals.md). Outer rings spin slowest
	# (rate grows with depth into the chain), so the inheritance reads: inner
	# rings whirl fast within the slowly-reorienting frame of the outer ones.
	var chain := Quaternion.IDENTITY
	for i in _rings.size():
		var axis: Vector3 = AXES[i % AXES.size()]
		var base_tilt := PI * float(i) / float(ring_count)
		var rate := RATE_BASE * (1.0 + i * 0.55)
		chain = chain * Quaternion(axis, base_tilt + _t * rate)
		_rings[i].transform.basis = Basis(chain) * MESH_CORR


func _rebuild() -> void:
	for r in _rings:
		r.queue_free()
	_rings.clear()
	if not is_inside_tree():
		return
	var mat := _style_material(style)
	for i in ring_count:
		# Chain index 0 = outermost. Radius shrinks as we go deeper into the
		# chain, so the parent ring is the big outer one (matches _process).
		var depth := ring_count - 1 - i
		var ring_r := base_radius * (1.0 + depth * RADIUS_STEP)
		# A rectangular-cross-section ring ("annular prism") — a flat band with a
		# nudge of radial thickness, NOT a round donut tube. Outer + inner walls +
		# two rims; the SOLID_GLYPH runes ride the inner wall (v across it), rims
		# bare. thickness == 0 degenerates to the old zero-thickness single wall.
		var mi := MeshInstance3D.new()
		mi.mesh = _build_band_mesh(ring_r, ring_r * band_width, ring_r * thickness, facets)
		mi.material_override = mat
		# The band's outer radius, for tests / callers (a custom ArrayMesh has no
		# top_radius the way CylinderMesh did).
		mi.set_meta(&"outer_radius", ring_r)
		add_child(mi)
		_rings.append(mi)
	_apply_tint()


# Builds one band as a rectangular-cross-section ring around the Y axis (so
# MESH_CORR still swings the axis to local Z, matching the 2D hoop). Four
# surfaces: outer wall (r=outer_r), inner wall (r=outer_r-thick), and top/bottom
# rims closing the ends. UV convention is what makes the glyph "rim-aware": the
# INNER wall carries v in [0,1] (the glyph band); every other surface is parked
# at v = OUTER_V (>1), where gimbal_glyph.gdshader's band mask is 0 — so runes
# only ever inscribe the inner face and the rims stay bare metal. thick <= 0
# collapses to a single wall (no inner wall / rims), the old thin slice.
const OUTER_V := 2.0

func _build_band_mesh(outer_r: float, height: float, thick: float, seg: int) -> ArrayMesh:
	var hy := height * 0.5
	var up := Vector3.UP
	var inner_r: float = maxf(outer_r - thick, 0.0)
	var solid := thick > 0.0001 and inner_r > 0.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var u0 := float(i) / float(seg)
		var u1 := float(i + 1) / float(seg)
		# Outer wall — normal points radially out; parked at OUTER_V (bare metal).
		_quad(st,
			d0 * outer_r + up * hy, d1 * outer_r + up * hy,
			d1 * outer_r - up * hy, d0 * outer_r - up * hy,
			d0, d1, d1, d0,
			Vector2(u0, OUTER_V), Vector2(u1, OUTER_V), Vector2(u1, OUTER_V), Vector2(u0, OUTER_V))
		if not solid:
			continue
		# Inner wall — normal points radially IN; carries the glyph band v in [0,1]
		# (top rim v=0, bottom rim v=1). Wound opposite the outer wall so its front
		# face looks inward (you read the far inner face through the near gap).
		_quad(st,
			d1 * inner_r + up * hy, d0 * inner_r + up * hy,
			d0 * inner_r - up * hy, d1 * inner_r - up * hy,
			-d1, -d0, -d0, -d1,
			Vector2(u1, 0.0), Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 1.0))
		# Top rim (y=+hy, normal +Y) and bottom rim (y=-hy, normal -Y), both bare.
		_quad(st,
			d0 * inner_r + up * hy, d1 * inner_r + up * hy,
			d1 * outer_r + up * hy, d0 * outer_r + up * hy,
			up, up, up, up,
			Vector2(u0, OUTER_V), Vector2(u1, OUTER_V), Vector2(u1, OUTER_V), Vector2(u0, OUTER_V))
		_quad(st,
			d0 * outer_r - up * hy, d1 * outer_r - up * hy,
			d1 * inner_r - up * hy, d0 * inner_r - up * hy,
			-up, -up, -up, -up,
			Vector2(u0, OUTER_V), Vector2(u1, OUTER_V), Vector2(u1, OUTER_V), Vector2(u0, OUTER_V))
	return st.commit()


# Two triangles (a,c,b)+(a,d,c) with per-vertex normals and UVs. Corners are
# given front-facing CW (Godot's actual front-face winding, confirmed
# empirically — see #239 follow-up) so a solid ring reads right-side-out under
# cull_back. The a/b/c/d corners + their normals/UVs still describe the
# quad in the caller's original (CCW-looking) order; only the emitted
# triangle vertex order is swapped, so callers need no changes.
func _quad(st: SurfaceTool,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for v in [[a, na, ua], [c, nc, uc], [b, nb, ub], [a, na, ua], [d, nd, ud], [c, nc, uc]]:
		st.set_normal(v[1])
		st.set_uv(v[2])
		st.add_vertex(v[0])


func _apply_tint() -> void:
	for r in _rings:
		r.set_instance_shader_parameter(&"tint", Vector3(tint.r, tint.g, tint.b))


static func _style_material(s: Style) -> ShaderMaterial:
	if _mats.has(s):
		return _mats[s]
	var paths := {
		Style.UNIFORM_GLOW: "res://skill_node/visuals/gimbal_3d/gimbal_uniform.gdshader",
		Style.HOLO_GLASS: "res://skill_node/visuals/gimbal_3d/gimbal_glass.gdshader",
		Style.SOLID_GLYPH: "res://skill_node/visuals/gimbal_3d/gimbal_glyph.gdshader",
	}
	var mat := ShaderMaterial.new()
	mat.shader = load(paths[s])
	if s == Style.SOLID_GLYPH:
		mat.set_shader_parameter(&"glyphs", _glyph_strip())
	_mats[s] = mat
	return mat


## Bakes a horizontal strip of procedural rune glyphs into the R channel once
## (shared across every rig, so a plain uniform sampler — not per-instance — and
## batching survives). Each cell is a handful of straight strokes on a 3x3 grid,
## deterministic so the runes are stable frame to frame.
static func _glyph_strip() -> ImageTexture:
	if _glyph_tex != null:
		return _glyph_tex
	const CELLS := 8
	const CELL := 64
	var w := CELLS * CELL
	var img := Image.create(w, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xADDED
	# 3x3 grid node positions inside a cell, with a margin.
	var margin := 14.0
	var span := float(CELL) - margin * 2.0
	for c in CELLS:
		var nodes: Array[Vector2] = []
		for gy in 3:
			for gx in 3:
				nodes.append(Vector2(margin + gx * span * 0.5, margin + gy * span * 0.5))
		var strokes := rng.randi_range(3, 5)
		var cur := rng.randi_range(0, nodes.size() - 1)
		for _s in strokes:
			var nxt := rng.randi_range(0, nodes.size() - 1)
			if nxt == cur:
				nxt = (nxt + 1) % nodes.size()
			var a := nodes[cur] + Vector2(c * CELL, 0)
			var b := nodes[nxt] + Vector2(c * CELL, 0)
			_stroke(img, a, b, 2.5)
			cur = nxt
	_glyph_tex = ImageTexture.create_from_image(img)
	return _glyph_tex


static func _stroke(img: Image, a: Vector2, b: Vector2, radius: float) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_stamp(img, p, radius)


static func _stamp(img: Image, p: Vector2, radius: float) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(dx, dy).length()
			if d > radius:
				continue
			var v := clampf(1.0 - d / radius, 0.0, 1.0)
			var existing := img.get_pixel(x, y).r
			img.set_pixel(x, y, Color(maxf(existing, v), 0, 0, 1))
