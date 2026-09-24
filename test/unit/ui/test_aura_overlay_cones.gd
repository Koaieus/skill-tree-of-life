extends GutTest

## #898 — AuraOverlay packs the owned INDUCED subgraph as rounded cones
## (#140 decisions 3, 6, 8): one degenerate `A == B` cone per owned node
## regardless of degree, plus one cone per edge whose two endpoints share an
## owner, tagged with that owner's entity index. A half-owned edge and an edge
## between two different owners emit nothing.
##
## The cone list is read back through the overlay's tile index — the same
## primitives the shader fetches — rather than a parallel accessor.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _AURA_SCENE := preload("res://ui/aura_overlay/aura_overlay.tscn")

var _graph: Graph
var _overlay: AuraOverlay


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_overlay = _AURA_SCENE.instantiate()
	add_child_autofree(_overlay)


func _entity(color: Color) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.color = color
	_graph.add_child(e)
	return e


func _node(pos: Vector2, owner: Entity, base_radius: float = 32.0) -> SkillNode:
	var sn: SkillNode = _SKILL_NODE_SCENE.instantiate()
	sn.position = pos
	sn.base_radius = base_radius
	sn.owned_by = owner
	_graph.add_skill_node(sn)
	return sn


## Every packed primitive as `[texel_a: Vector4, texel_b: Vector4]`.
func _packed_cones() -> Array:
	var out: Array = []
	for i in _overlay._tile_index.primitive_count:
		out.append(_overlay._tile_index.get_cone(i))
	return out


func _is_degenerate(cone: Array) -> bool:
	var a: Vector4 = cone[0]
	var b: Vector4 = cone[1]
	return Vector2(a.x, a.y) == Vector2(b.x, b.y) and is_equal_approx(a.z, b.z)


func _segments(cones: Array) -> Array:
	var out: Array = []
	for c in cones:
		if not _is_degenerate(c):
			out.append(c)
	return out


func test_owned_induced_subgraph_packs_nodes_and_same_owner_edges_only() -> void:
	var red := _entity(Color.RED)
	var blue := _entity(Color.BLUE)
	# Path r1 - r2 - r3 owned by red; r3 - n (unowned): half-owned, nothing.
	# r3 - b1: two owners, nothing. b1 - b2 owned by blue. iso: isolated, red.
	var r1 := _node(Vector2(0, 0), red)
	var r2 := _node(Vector2(200, 0), red)
	var r3 := _node(Vector2(400, 0), red)
	var n := _node(Vector2(400, 200), null)
	var b1 := _node(Vector2(600, 0), blue)
	var b2 := _node(Vector2(800, 0), blue)
	var iso := _node(Vector2(0, 400), red)
	_graph.add_edge(r1, r2)
	_graph.add_edge(r2, r3)
	_graph.add_edge(r3, n)
	_graph.add_edge(r3, b1)
	_graph.add_edge(b1, b2)

	_overlay.edge_width = 1.0
	_overlay.edge_slack_length = INF
	_overlay.graph = _graph

	var cones := _packed_cones()
	# 6 owned nodes (n is unowned) + 3 same-owner edges.
	assert_eq(cones.size(), 6 + 3, "one degenerate per owned node + one cone per same-owner edge")

	var degenerates: Array = []
	for c in cones:
		if _is_degenerate(c):
			degenerates.append(c)
	assert_eq(degenerates.size(), 6, "every owned node ships as an A == B cone, isolated ones included")

	# Entity indices follow first-seen owner order: red = 0, blue = 1.
	var red_idx := 0.0
	var blue_idx := 1.0
	var mat: ShaderMaterial = _overlay.material
	assert_eq((mat.get_shader_parameter(&"entity_colors") as Array)[0],
		Emissive.tint_damped(red.color, Emissive.INERT), "entity 0 is red")

	var iso_seen := false
	for c in degenerates:
		var a: Vector4 = c[0]
		if Vector2(a.x, a.y) == iso.global_position:
			iso_seen = true
			assert_eq(a.w, red_idx, "the isolated node is tagged with red's index")
			assert_almost_eq(a.z, iso.radius * _overlay.radius_multiplier, 1e-4,
				"a node disc uses the aura radius")
	assert_true(iso_seen, "an isolated owned node must not vanish")

	var segs := _segments(cones)
	assert_eq(segs.size(), 3, "r1-r2, r2-r3, b1-b2 — nothing for r3-n or r3-b1")
	var seen_pairs: Dictionary = {}
	for c in segs:
		var a: Vector4 = c[0]
		var b: Vector4 = c[1]
		var key := [Vector2(a.x, a.y), Vector2(b.x, b.y)]
		seen_pairs[key] = a.w
	assert_eq(seen_pairs.get([r1.global_position, r2.global_position]), red_idx, "r1-r2 tagged red")
	assert_eq(seen_pairs.get([r2.global_position, r3.global_position]), red_idx, "r2-r3 tagged red")
	assert_eq(seen_pairs.get([b1.global_position, b2.global_position]), blue_idx, "b1-b2 tagged blue")
	assert_false(seen_pairs.has([r3.global_position, n.global_position]), "half-owned edge emits nothing")
	assert_false(seen_pairs.has([r3.global_position, b1.global_position]), "two-owner edge emits nothing")


## Decision 8: cone end radius = aura disc radius × w, w = edge_width / (1 + L / edge_slack_length).
## An edge exactly `edge_slack_length` long therefore packs at half `edge_width`.
func test_edge_radii_pinch_with_length() -> void:
	var red := _entity(Color.RED)
	var a := _node(Vector2(0, 0), red, 32.0)
	var b := _node(Vector2(300, 0), red, 48.0)
	_graph.add_edge(a, b)
	_overlay.edge_width = 0.6
	_overlay.edge_slack_length = 300.0
	_overlay.graph = _graph

	var segs := _segments(_packed_cones())
	assert_eq(segs.size(), 1)
	var ta: Vector4 = segs[0][0]
	var tb: Vector4 = segs[0][1]
	var w := 0.6 / 2.0
	assert_almost_eq(ta.z, a.radius * _overlay.radius_multiplier * w, 1e-4,
		"end A radius = disc radius × edge_width / (1 + L / slack) with L == slack")
	assert_almost_eq(tb.z, b.radius * _overlay.radius_multiplier * w, 1e-4,
		"end B radius scales the same way off its own disc radius")
	assert_ne(ta.z, tb.z, "unequal stake radii taper the cone")

	# INF slack disables the pinch: plain edge_width.
	_overlay.edge_slack_length = INF
	var flat: Vector4 = _segments(_packed_cones())[0][0]
	assert_almost_eq(flat.z, a.radius * _overlay.radius_multiplier * 0.6, 1e-4,
		"INF slack → w == edge_width")


## Same-coloured owners (every blocker is the same grey) are one aura: one
## colour slot, and an edge between two of them joins their territories — so
## fifty blockers never crowd the players out of the colour cap.
func test_same_coloured_owners_share_one_slot_and_join_across_edges() -> void:
	var grey_a := _entity(Color.GRAY)
	var grey_b := _entity(Color.GRAY)
	var red := _entity(Color.RED)
	var a := _node(Vector2(0, 0), grey_a)
	var b := _node(Vector2(200, 0), grey_b)
	var r := _node(Vector2(400, 0), red)
	_graph.add_edge(a, b)
	_graph.add_edge(b, r)

	_overlay.edge_width = 1.0
	_overlay.edge_slack_length = INF
	_overlay.graph = _graph

	var mat: ShaderMaterial = _overlay.material
	assert_eq(int(mat.get_shader_parameter(&"entity_count")), 2, "grey + red — the two greys share a slot")
	var segs := _segments(_packed_cones())
	assert_eq(segs.size(), 1, "a-b joins (same colour); b-r does not")
	var sa: Vector4 = segs[0][0]
	assert_eq(sa.w, 0.0, "the joined edge carries the shared grey slot")
