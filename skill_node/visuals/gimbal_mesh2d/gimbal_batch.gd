@tool
class_name GimbalBatch
extends Node2D
## Shape-B spike (#1075): every gimbal on a canvas drawn from ONE shared
## `MultiMesh`, referenced by two `MultiMeshInstance2D`s (`Back`: the half
## behind the node disk, z just below GRAPH_DEFAULT; `Front`: the half in front,
## just above), rotated and projected per vertex by `gimbal_mesh2d.gdshader`.
## Per-frame CPU cost is zero: the CPU writes an instance only when a gimbal
## appears, moves or changes params. The edge-mesh precedent (`Graph.edge_mesh`)
## with a free-list instead of swap-with-last, so a slot index is stable for
## the owner's lifetime.
##
## Per-instance channels (see the shader header):
##   transform_2d    = world position + uniform scale (the unit ring radius, px)
##   COLOR           = tint, HDR-lifted through `Emissive.at`
##   INSTANCE_CUSTOM = (phase, spin_speed, ring_count, style)
##
## The mesh is baked ONCE for MAX_RINGS rings; a ring at index >= an
## instance's ring_count collapses to a point in the vertex shader.

const MAX_RINGS := 5
## Facets per ring at x1; the bench env knob GIMBAL_MESH2D_FACETS=<N>
## multiplies it (read once, when the shared mesh is baked).
const FACETS := 24
## Ring cross-section, as fractions of the ring's own radius (axial height
## and radial thickness — the annular prism `gimbal_3d.gd:_build_band_mesh`
## builds), and the radius growth per ring outward. The step matches the 2D
## CoreHalos GIMBAL layout so the staged footprint (fill) is comparable.
const BAND_WIDTH := 0.22
const THICKNESS := 0.06
const RADIUS_STEP := 0.22
## UV.y for every surface that is NOT the inner wall (glyph band mask = 0).
const OUTER_V := 2.0

enum Style { HOLO_GLASS = 1, SOLID_GLYPH = 2 }

const _SHADER := preload("res://skill_node/visuals/gimbal_mesh2d/gimbal_mesh2d.gdshader")
const _Z := preload("res://ui/z_layers.gd")
const _GIMBAL_3D := preload("res://skill_node/visuals/gimbal_3d/gimbal_3d.gd")

static var _baked_mesh: ArrayMesh

@onready var back: MultiMeshInstance2D = $Back
@onready var front: MultiMeshInstance2D = $Front

var _mm: MultiMesh
var _slot: Dictionary = {}       # owner -> int
var _free: Array[int] = []
var _capacity: int = 0
var _high_water: int = 0        # slots ever handed out (free list draws below it)


func _ready() -> void:
	add_to_group(&"gimbal_batch")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _mesh()
	_mm.instance_count = 0
	back.multimesh = _mm
	front.multimesh = _mm
	back.z_index = _Z.GRAPH_DEFAULT - 1
	front.z_index = _Z.GRAPH_DEFAULT + 1
	back.material = _material(0.0)
	front.material = _material(1.0)


## The canvas' one batch: the nearest `Graph` ancestor of `node` (else its
## parent) hosts it, instanced lazily on first ask.
static func ensure_for(node: Node) -> GimbalBatch:
	var host: Node = node.get_parent()
	var walk := host
	while walk != null:
		if walk is Graph:
			host = walk
			break
		walk = walk.get_parent()
	for child in host.get_children():
		if child is GimbalBatch:
			return child
	var batch: GimbalBatch = load("res://skill_node/visuals/gimbal_mesh2d/gimbal_batch.tscn").instantiate()
	host.add_child(batch)
	return batch


## Stable slot index for the owner, growing the buffer when needed.
func acquire(owner: Object) -> int:
	if _slot.has(owner):
		return _slot[owner]
	var idx: int
	if not _free.is_empty():
		idx = _free.pop_back()
	else:
		idx = _high_water
		_high_water += 1
		_grow_capacity(_high_water)
	_slot[owner] = idx
	return idx


## Frees the owner's slot (collapsed to a zero transform so it draws nothing);
## the index is reused by the next `acquire`.
func release(owner: Object) -> void:
	var idx: int = _slot.get(owner, -1)
	if idx == -1:
		return
	_slot.erase(owner)
	_free.append(idx)
	if _mm != null:
		_mm.set_instance_transform_2d(idx, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))


func slot_of(owner: Object) -> int:
	return _slot.get(owner, -1)


## Live (acquired) slot count.
func live_count() -> int:
	return _slot.size()


## Allocated GPU buffer capacity (`MultiMesh.instance_count`).
func capacity() -> int:
	return _capacity


## Facets per ring of the baked mesh (FACETS x the env multiplier).
static func facets() -> int:
	return FACETS * maxi(1, int(OS.get_environment("GIMBAL_MESH2D_FACETS")))


## Vertex count of the shared baked mesh (all MAX_RINGS rings).
func mesh_vertex_count() -> int:
	return _mm.mesh.surface_get_array_len(0)


## `radius` is the unit ring radius in px (ring i sits at radius * (1 + i*step)).
func set_slot_transform(slot: int, world_pos: Vector2, radius: float) -> void:
	_mm.set_instance_transform_2d(slot, Transform2D(0.0, Vector2(radius, radius), 0.0, world_pos))


func set_slot_params(slot: int, tint: Color, ring_count: int, style: Style,
		phase: float = 0.0, spin_speed: float = 1.0) -> void:
	_mm.set_instance_color(slot, Emissive.at(tint, Emissive.VALUE))
	_mm.set_instance_custom_data(slot, Color(phase, spin_speed, float(ring_count), float(style)))


## Grown by doubling, never shrunk: every write to `instance_count` discards
## the GPU buffer, so the live instances are copied back afterwards.
func _grow_capacity(min_count: int) -> void:
	if min_count <= _capacity:
		return
	var saved: Array = []
	for i in _high_water - 1:
		saved.append([_mm.get_instance_transform_2d(i), _mm.get_instance_color(i),
				_mm.get_instance_custom_data(i)])
	_capacity = maxi(min_count, maxi(_capacity * 2, 8))
	_mm.instance_count = _capacity
	for i in saved.size():
		_mm.set_instance_transform_2d(i, saved[i][0])
		_mm.set_instance_color(i, saved[i][1])
		_mm.set_instance_custom_data(i, saved[i][2])
	# A fresh slot must not draw the mesh at identity until its owner writes it.
	for i in range(saved.size(), _capacity):
		_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))


func _material(front_pass: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter(&"front_pass", front_pass)
	mat.set_shader_parameter(&"glyphs", _GIMBAL_3D._glyph_strip())
	return mat


## The band mesh for MAX_RINGS rings, baked once and shared. Canvas VERTEX is a
## vec2, so each vertex carries its ring-local 3D description in the custom
## channels (the channel verdict of #1075 — CUSTOM0/CUSTOM1 are canvas vertex
## built-ins from 4.4 on):
##   CUSTOM0 = (cos a, sin a, radial: 0 outer wall / 1 inner wall, ring index)
##   CUSTOM1 = (axial sign ±1, is_rim 0/1, normal sign ±1, 0)
##   UV      = (a / TAU, v: [0,1] across the inner wall, OUTER_V elsewhere)
##   VERTEX  = the direction at the outermost radius — only the AABB reads it
static func _mesh() -> ArrayMesh:
	if _baked_mesh != null:
		return _baked_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var r_max := (1.0 + float(MAX_RINGS - 1) * RADIUS_STEP) * 1.05
	var seg := facets()
	for ring in MAX_RINGS:
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var u0 := float(i) / float(seg)
			var u1 := float(i + 1) / float(seg)
			# Corners as [angle, u, axial sign, radial]; normal per surface.
			# Outer wall: normal radially out.
			_quad(st, ring, r_max, [[a0, u0, 1.0, 0.0], [a1, u1, 1.0, 0.0], [a1, u1, -1.0, 0.0], [a0, u0, -1.0, 0.0]],
					0.0, 1.0, OUTER_V, OUTER_V)
			# Inner wall: normal radially in, glyph v across it.
			_quad(st, ring, r_max, [[a1, u1, 1.0, 1.0], [a0, u0, 1.0, 1.0], [a0, u0, -1.0, 1.0], [a1, u1, -1.0, 1.0]],
					0.0, -1.0, 0.0, 1.0)
			# Top rim (+axial) and bottom rim (-axial).
			_quad(st, ring, r_max, [[a0, u0, 1.0, 1.0], [a1, u1, 1.0, 1.0], [a1, u1, 1.0, 0.0], [a0, u0, 1.0, 0.0]],
					1.0, 1.0, OUTER_V, OUTER_V)
			_quad(st, ring, r_max, [[a0, u0, -1.0, 0.0], [a1, u1, -1.0, 0.0], [a1, u1, -1.0, 1.0], [a0, u0, -1.0, 1.0]],
					1.0, -1.0, OUTER_V, OUTER_V)
	_baked_mesh = st.commit()
	return _baked_mesh


static func _quad(st: SurfaceTool, ring: int, r_max: float, c: Array,
		is_rim: float, n_sign: float, v_top: float, v_bottom: float) -> void:
	# (a, c, b) + (a, d, c): the canvas has no culling, winding is free.
	for k in [0, 2, 1, 0, 3, 2]:
		var corner: Array = c[k]
		var ang: float = corner[0]
		st.set_custom(0, Color(cos(ang), sin(ang), corner[3], float(ring)))
		st.set_custom(1, Color(corner[2], is_rim, n_sign, 0.0))
		st.set_uv(Vector2(corner[1], v_top if k < 2 else v_bottom))
		st.add_vertex(Vector3(cos(ang) * r_max, sin(ang) * r_max, 0.0))
