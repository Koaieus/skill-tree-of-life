extends GutTest

## Coverage for [VisionSystem] — sensed traversal, empty-mode policies, edge
## sensing, input gating, and the vision-source animation lifecycle — plus the
## [Graph] adjacency index [method Graph.get_neighbours] reads.
##
## The traversal is a max-budget priority walk implemented as a bucket sort
## (budget → nodes reached with that many hops left). These tests pin the
## observable contract: reach = budget in hops, owned/visible nodes are never
## "sensed", multiple sources union their reach, and the budget decays one hop
## at a time.
##
## Nodes are placed 2000px apart so the default `vision_range` (~504px) only
## ever reaches a node's own position — that isolates sensing from vision.
## `_place_nodes_within_vision()` collapses the spacing when a test needs the
## opposite.
##
## The fixture deliberately leaves `allocation_system` unset on the system, so
## `force_allocate` does not trigger a deferred recompute — every test drives
## `_recompute()` explicitly and asserts on a settled state.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _SPACING := 2000.0

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# Path graph: N0 – N1 – N2 – N3 – N4
	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * _SPACING, 0.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 4:
		_add_edge(_nodes[i], _nodes[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	_vision = VisionSystem.new()
	_vision.graph = _graph
	add_child_autofree(_vision)
	await get_tree().process_frame


func _add_edge(a: SkillNode, b: SkillNode) -> Edge:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
	return e


## `sensor_range` is a derived stat (the board adds a PER-scaled term on top of
## `base_value`), so setting the base doesn't set the hop budget. Solve for the
## base that lands the *effective* local value on `hops`. Requires the node to
## already be owned — `get_local_value` reads through the owner's board.
func _set_budget(hops: int) -> void:
	var s: Stat = _entity.stat_board.get_stat(&"sensor_range")
	s.base_value = 0.0
	var derived: float = float(_nodes[0].get_local_value(&"sensor_range"))
	s.base_value = float(hops) - derived
	assert_eq(int(_nodes[0].get_local_value(&"sensor_range")), hops,
		"fixture: effective sensor_range should be %d hops" % hops)


## Own `owned_indices`, sense with `hops` budget. Returns sensed node names.
func _sensed_names(hops: int, owned_indices: Array = [0]) -> Array:
	for i in owned_indices:
		_alloc.force_allocate(_entity, _nodes[i])
	_set_budget(hops)
	_vision.viewers = [_entity]
	_vision._recompute()
	var out: Array = []
	for n in _nodes:
		if _vision.is_sensed(n):
			out.append(String(n.name))
	return out


func test_sensed_reach_equals_hop_budget() -> void:
	assert_eq(_sensed_names(2), ["N1", "N2"],
		"2 hops from N0 senses N1 and N2, stops before N3")


func test_zero_budget_senses_nothing() -> void:
	assert_eq(_sensed_names(0), [], "no sensor budget senses nothing")


func test_owned_node_is_visible_not_sensed() -> void:
	_sensed_names(2)
	assert_true(_vision.is_visible(_nodes[0]), "the owned source is visible")
	assert_false(_vision.is_sensed(_nodes[0]), "an owned node is never merely sensed")


func test_multiple_sources_union_their_reach() -> void:
	# Own both ends of the path with 1 hop each: N0 reaches N1, N4 reaches N3.
	# N2 sits 2 hops from either and stays unsensed.
	assert_eq(_sensed_names(1, [0, 4]), ["N1", "N3"],
		"each source contributes its own 1-hop ring")


func test_budget_is_spent_per_hop_from_the_source() -> void:
	# 3 hops from N0 reaches N3 but not N4. If an intermediate node re-seeded
	# the walk with a fresh budget, N4 would leak in.
	assert_eq(_sensed_names(3), ["N1", "N2", "N3"],
		"the walk decays one hop at a time and stops exactly at the budget")


# ── Vision (radius), as opposed to sensing (hops) ─────────────────────────

## Collapse the path so every node falls inside the default `vision_range`.
func _place_nodes_within_vision() -> void:
	for i in _nodes.size():
		_nodes[i].position = Vector2(i * 100.0, 0.0)


func test_vision_reaches_every_node_inside_the_radius() -> void:
	_place_nodes_within_vision()
	_alloc.force_allocate(_entity, _nodes[0])
	_vision.viewers = [_entity]
	_vision._recompute()
	for n in _nodes:
		assert_true(_vision.is_visible(n), "%s is within vision_range of N0" % n.name)
		assert_false(_vision.is_sensed(n), "a visible node is never merely sensed")


func test_node_local_vision_modifier_buffs_only_that_node() -> void:
	# A Spyglass-style addon puts a `vision_range` modifier on ONE node's sparse
	# node_board. That node sees further; its owner's other nodes do not.
	_alloc.force_allocate(_entity, _nodes[0])
	_alloc.force_allocate(_entity, _nodes[1])

	var spyglass := StatModifier.new()
	spyglass.stat_id = &"vision_range"
	spyglass.operation = StatModifier.Operation.ADD_BASE
	spyglass.value = _SPACING  # enough to reach one more node along the path
	_nodes[1]._ensure_local_stat(&"vision_range")
	_nodes[1].node_board.add_modifier(spyglass)

	_set_budget(0)  # sensing off — this test is about vision radius only
	_vision.viewers = [_entity]
	_vision._recompute()

	assert_true(_vision.is_visible(_nodes[2]),
		"N2 is inside the buffed N1's vision_range")
	assert_false(_vision.is_visible(_nodes[4]),
		"N0 and N3 are unbuffed, so N4 stays dark — the buff is node-local")


# ── Input gating ──────────────────────────────────────────────────────────

func test_input_pickable_tracks_visibility() -> void:
	_sensed_names(1)  # own N0, sense N1; N2..N4 unreached
	assert_true(_nodes[0].input_pickable, "the visible owned node is clickable")
	assert_false(_nodes[1].input_pickable, "a sensed-only node is not clickable")
	assert_false(_nodes[4].input_pickable, "an unreached node is not clickable")


func test_revealed_tracks_full_visibility_not_just_sensed() -> void:
	# own N0 (visible), sense N1, N2..N4 unreached (darkness).
	_sensed_names(1)
	assert_true(_nodes[0].revealed, "the visible owned node is revealed")
	assert_false(_nodes[1].revealed, "a sensed-only node is not revealed")
	# Regression (#94): a fully-fogged node has sensed == false too, so gating
	# readable detail (the core HP bar) on `not sensed` would leak it through
	# darkness. `revealed` is the correct gate — it stays false here.
	assert_false(_nodes[4].sensed, "an unreached node is not even sensed")
	assert_false(_nodes[4].revealed, "an unreached (darkness) node is not revealed")


# ── Edge sensing ──────────────────────────────────────────────────────────

func _edge_between(a: SkillNode, b: SkillNode) -> Edge:
	for e in _graph.get_edges():
		if (e.from == a and e.to == b) or (e.from == b and e.to == a):
			return e
	return null


func test_edge_is_sensed_only_when_exactly_one_endpoint_is_visible() -> void:
	# Own N0 (visible), sense N1 and N2. N3+ unreached.
	_sensed_names(2)
	assert_true(_edge_between(_nodes[0], _nodes[1]).sensed,
		"visible → sensed edge is a breadcrumb")
	assert_true(_edge_between(_nodes[1], _nodes[2]).sensed,
		"sensed → sensed edge is a breadcrumb")
	assert_false(_edge_between(_nodes[2], _nodes[3]).sensed,
		"an edge with an unreached endpoint stays hidden — it would leak topology")


## An edge straddling the vision boundary — one endpoint in vision range, the
## other neither visible nor sensed — must still RENDER. It is not `sensed`
## (that channel needs both endpoints reached, per the test above), so if
## `vision_visible` also comes out false the edge lands in `VIS_HIDDEN` and
## `edge_mesh.gdshader` hard-zeroes its alpha — a visible node then draws with
## no connecting edges at all. `FogOverlay` used to AND the two endpoints here;
## the shader's `VIS_VISIBLE` branch already fades the quad per-fragment against
## the vision field, so OR is the correct gate and the far half dims itself.
func test_edge_leaving_vision_still_renders() -> void:
	# Default fixture spacing (2000px) vs vision_range (~504px): owning N0 makes
	# exactly N0 visible. Budget 0 means nothing is sensed, so N1 is unreached.
	_sensed_names(0)
	assert_true(_vision.is_visible(_nodes[0]), "fixture: N0 is the only visible node")
	assert_false(_vision.is_visible(_nodes[1]), "fixture: N1 is outside vision range")
	assert_false(_vision.is_sensed(_nodes[1]), "fixture: N1 is unreached, not sensed")

	var fog := preload("res://ui/fog_overlay/fog_overlay.tscn").instantiate() as FogOverlay
	fog.vision_system = _vision
	add_child_autofree(fog)
	await get_tree().process_frame
	fog._refresh()

	var straddling := _edge_between(_nodes[0], _nodes[1])
	assert_false(straddling.sensed, "one endpoint unreached — not a sensed breadcrumb")
	assert_true(straddling.vision_visible,
		"an edge with ONE endpoint in vision must render, or N0 looks unconnected")
	assert_eq(straddling.render_vis_state, Edge.VIS_VISIBLE,
		"and it must reach the shader branch that fades per-fragment, not VIS_HIDDEN")

	var far := _edge_between(_nodes[2], _nodes[3])
	assert_false(far.vision_visible,
		"an edge with NEITHER endpoint in vision is still genuinely hidden")


func test_edge_between_two_visible_nodes_is_not_sensed() -> void:
	# Both endpoints visible → the edge renders normally, not as a breadcrumb.
	_place_nodes_within_vision()
	_alloc.force_allocate(_entity, _nodes[0])
	_vision.viewers = [_entity]
	_vision._recompute()
	assert_false(_edge_between(_nodes[0], _nodes[1]).sensed,
		"both-visible edges render lit/unlit by ownership, not as breadcrumbs")


# ── Empty-mode policies ───────────────────────────────────────────────────

func test_empty_mode_off_marks_everything_visible() -> void:
	_vision.empty_mode = VisionSystem.EmptyMode.OFF
	_vision._recompute()
	for n in _nodes:
		assert_true(_vision.is_visible(n), "OFF is the inert 'no fog' switch")
	assert_false(_vision.should_render_fog(), "OFF skips the fullscreen fog pass")


func test_empty_mode_darkness_marks_nothing_visible() -> void:
	_vision.empty_mode = VisionSystem.EmptyMode.DARKNESS
	_vision._recompute()
	for n in _nodes:
		assert_false(_vision.is_visible(n), "DARKNESS reveals nothing")
	assert_true(_vision.should_render_fog())


func test_empty_mode_all_entities_sweeps_the_group() -> void:
	# No explicit viewer; the entity is discovered via group("entities").
	_place_nodes_within_vision()
	_alloc.force_allocate(_entity, _nodes[0])
	_vision.empty_mode = VisionSystem.EmptyMode.ALL_ENTITIES
	_vision._recompute()
	assert_true(_vision.is_visible(_nodes[0]),
		"the ungated entity acts as a viewer")
	assert_true(_vision.should_render_fog())


func test_explicit_viewers_win_over_empty_mode() -> void:
	_place_nodes_within_vision()
	_alloc.force_allocate(_entity, _nodes[0])
	_vision.empty_mode = VisionSystem.EmptyMode.OFF
	_vision.viewers = [_entity]
	_vision._recompute()
	assert_true(_vision.should_render_fog(),
		"a populated viewer list means OFF's inert path never applies")


# ── Vision-source animation lifecycle ─────────────────────────────────────

func test_sources_fade_in_from_zero_radius() -> void:
	_place_nodes_within_vision()
	_alloc.force_allocate(_entity, _nodes[0])
	_vision.viewers = [_entity]
	_vision._recompute()
	assert_eq(_vision.get_vision_sources().size(), 0,
		"a brand-new circle starts at radius 0 and isn't rendered yet")
	# A short tick: the circle has grown but is still short of its target, so it
	# reports non-zero `motion` — that's what paints the frontier halo.
	_vision._process(0.02)
	var mid := _vision.get_vision_sources()
	assert_eq(mid.size(), 1, "after a tick the circle has grown")
	assert_gt(float(mid[0].radius), 0.0)
	assert_gt(float(mid[0].motion), 0.0, "an in-flight circle drives the frontier glow")

	# Settle it: motion decays to nothing once the radius reaches its target.
	for _i in 20:
		_vision._process(1.0)
	assert_almost_eq(float(_vision.get_vision_sources()[0].motion), 0.0, 0.001,
		"a settled circle has no frontier glow")


func test_deallocated_source_retreats_then_retires() -> void:
	_place_nodes_within_vision()
	_alloc.force_allocate(_entity, _nodes[0])
	_vision.viewers = [_entity]
	_vision._recompute()
	_vision._process(1.0)  # grow in
	assert_eq(_vision.get_vision_sources().size(), 1, "seeded")

	_alloc.force_deallocate(_nodes[0])
	_vision._recompute()
	assert_eq(_vision.get_vision_sources().size(), 1,
		"a dropped source lingers so it can animate out rather than pop")
	_vision._process(1.0)
	assert_eq(_vision.get_vision_sources().size(), 0,
		"once it reaches zero radius it retires")


# ── Graph adjacency index ─────────────────────────────────────────────────

func test_neighbours_of_path_interior_and_ends() -> void:
	assert_eq(_graph.get_neighbours(_nodes[0]), [_nodes[1]] as Array[SkillNode])
	assert_eq(_graph.get_neighbours(_nodes[2]), [_nodes[1], _nodes[3]] as Array[SkillNode])


func test_adjacency_index_refreshes_after_edge_added() -> void:
	_add_edge(_nodes[0], _nodes[4])
	assert_eq(_graph.get_neighbours(_nodes[0]), [_nodes[1], _nodes[4]] as Array[SkillNode],
		"a new edge invalidates the cached adjacency")


func test_adjacency_index_refreshes_after_edge_removed() -> void:
	assert_eq(_graph.get_neighbours(_nodes[1]).size(), 2, "seeded before removal")
	_graph.remove_edge(_graph.get_edges()[0])  # N0 – N1
	assert_eq(_graph.get_neighbours(_nodes[1]), [_nodes[2]] as Array[SkillNode],
		"a removed edge invalidates the cached adjacency")
	assert_eq(_graph.get_neighbours(_nodes[0]), [] as Array[SkillNode])


func test_self_loop_counts_each_endpoint_independently() -> void:
	_add_edge(_nodes[0], _nodes[0])
	assert_eq(_graph.get_neighbours(_nodes[0]), [_nodes[1], _nodes[0], _nodes[0]] as Array[SkillNode],
		"a self-loop contributes the node twice (degree +2)")


func test_returned_neighbours_are_not_the_cached_array() -> void:
	var first := _graph.get_neighbours(_nodes[2])
	first.clear()
	assert_eq(_graph.get_neighbours(_nodes[2]).size(), 2,
		"mutating a returned array must not corrupt the index")
