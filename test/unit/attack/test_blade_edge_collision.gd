extends GutTest

## #785 — blade EDGES collide, as swept capsules, and `edge_damage` is its own
## stat. Two defects this closes, both named on the issue:
##
##   1. [b]Straddle.[/b] A truss blade slams into a bunker and the initial nodes
##      pass either side of it — with vertex-only hitboxes it slips between them
##      and only bites deeper in the sweep, "causing bounces and largely chaotic
##      behavior" (owner, 2026-09-07). An edge capsule catches it on contact.
##   2. [b]Spacing luck.[/b] Whether a spike bit used to depend on whether the
##      defender happened to land on a vertex disk or in the gap between two —
##      invisible, unchosen, and it cut both ways. With the segment covered,
##      every offset along it contacts.
##
## Geometry is tested against a STATIC two-sample trajectory rather than a real
## swing: the capsule maths is a fact about a pose, and pinning it without the
## sim keeps these assertions independent of solver tuning (#790) and of
## physics-server sync timing.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


## A held pose: two identical samples, so `scan` runs its full element loop
## exactly once at a geometry we chose by hand.
func _held_pose(positions: Array[Vector2]) -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = 0.1
	traj.samples = [PackedVector2Array(positions), PackedVector2Array(positions)]
	return traj


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _events_on(events: Array[BladeHitEvent], target: SkillNode) -> Array[BladeHitEvent]:
	var out: Array[BladeHitEvent] = []
	for ev in events:
		if ev.target == target:
			out.append(ev)
	return out


# ── Defect 1: the straddle ─────────────────────────────────────────────────

## Pivot(0,0) ── Arm(400,0), target parked at the MIDPOINT. Neither vertex disk
## comes anywhere near it (node radii are tens of px, the gap is hundreds), so
## before #785 this scan returned nothing at all.
func test_a_target_between_two_vertices_is_contacted_by_the_connecting_edge() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn(graph, "Arm", Vector2(400.0, 0.0))
	var target := _spawn(graph, "Target", Vector2(200.0, 0.0))
	await _settle()

	assert_lt(pivot.radius + arm.radius, 200.0,
			"fixture assumption: the target sits in the GAP, clear of both vertex disks")

	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(400.0, 0.0)]
	var state := BladeState.build(
			positions, 0, [Vector2i(0, 1)], [pivot.radius, arm.radius])
	var events := BladeHitScan.scan(
			_held_pose(positions), state, pivot.get_world_2d().direct_space_state, graph)

	var on_target := _events_on(events, target)
	assert_eq(on_target.size(), 1, "the straddled target must be contacted exactly once")
	assert_true(on_target[0].is_edge_hit(), "and by the EDGE, since no vertex reaches it")
	assert_eq(on_target[0].edge_idx, 0)


# ── Defect 2: spacing luck ─────────────────────────────────────────────────

## The same pose, walking the target the whole length of the segment. Under
## vertex-only contact the answer flipped between "hit" and "miss" purely on
## where the node happened to sit; now every offset connects.
func test_contact_no_longer_depends_on_where_along_the_segment_a_target_sits() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn(graph, "Arm", Vector2(400.0, 0.0))
	var targets: Array[SkillNode] = []
	for offset in [60.0, 120.0, 180.0, 240.0, 300.0, 340.0]:
		targets.append(_spawn(graph, "T%d" % int(offset), Vector2(offset, -600.0)))
	await _settle()

	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(400.0, 0.0)]
	var state := BladeState.build(
			positions, 0, [Vector2i(0, 1)], [pivot.radius, arm.radius])
	var space_state := pivot.get_world_2d().direct_space_state
	# One target at a time, moved onto the segment — parking all six on the line
	# at once would test six simultaneous colliders, not six spacings.
	for target in targets:
		var home := target.global_position
		target.global_position = Vector2(home.x, 0.0)
		await get_tree().physics_frame
		var events := BladeHitScan.scan(_held_pose(positions), state, space_state, graph)
		assert_eq(_events_on(events, target).size(), 1,
				"a target at x=%.0f along the segment must contact" % home.x)
		target.global_position = home
		await get_tree().physics_frame


# ── Acceptance 2: a hub deals vertex damage, not vertex + one per spoke ────

## Six spokes out of one hub, target sitting ON the hub. The capsules are
## trimmed back to the rim of each endpoint's own disk, and the anti-double-dip
## rule caps the substep at one contact regardless — so a degree-6 hub is worth
## one vertex hit, never seven.
func test_a_target_on_a_hub_takes_one_vertex_contact_not_one_per_spoke() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var hub := _spawn(graph, "Hub", Vector2.ZERO)
	var target := _spawn(graph, "Target", Vector2.ZERO)
	var positions: Array[Vector2] = [Vector2.ZERO]
	var radii: Array[float] = [hub.radius]
	var edges: Array[Vector2i] = []
	for k in 6:
		var spoke_pos := Vector2.RIGHT.rotated(TAU * float(k) / 6.0) * 300.0
		var spoke := _spawn(graph, "Spoke%d" % k, spoke_pos)
		positions.append(spoke_pos)
		radii.append(spoke.radius)
		edges.append(Vector2i(0, k + 1))
	await _settle()

	var state := BladeState.build(positions, 0, edges, radii)
	state.vertex_damage[0] = 5.0
	for e_idx in state.edges.size():
		state.edge_damage[e_idx] = 3.0  # sharpened, so the spokes are NOT free
	var events := BladeHitScan.scan(
			_held_pose(positions), state, hub.get_world_2d().direct_space_state, graph)

	var on_target := _events_on(events, target)
	assert_eq(on_target.size(), 1, "the hub is worth ONE contact, not 1 + degree")
	assert_false(on_target[0].is_edge_hit(), "and it is the vertex's, the highest-damage one")
	assert_eq(on_target[0].particle_idx, 0)


# ── Acceptance 3: overlapping capsules take the higher, never the sum ──────

## Two edges splayed at a narrow angle off a shared hub, with a target just
## outside the hub's disk and inside BOTH capsules. The higher `edge_damage`
## wins outright; nothing is summed and the loser does not come back for a
## second bite on a later substep.
func test_a_target_inside_two_capsules_takes_the_higher_one_only() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var hub := _spawn(graph, "Hub", Vector2.ZERO)
	var a := _spawn(graph, "A", Vector2.RIGHT.rotated(0.04) * 400.0)
	var b := _spawn(graph, "B", Vector2.RIGHT.rotated(-0.04) * 400.0)
	var target := _spawn(graph, "Target", Vector2(200.0, 0.0))
	await _settle()

	var positions: Array[Vector2] = [
			Vector2.ZERO, a.global_position, b.global_position]
	var state := BladeState.build(
			positions, 0, [Vector2i(0, 1), Vector2i(0, 2)],
			[hub.radius, a.radius, b.radius])
	state.edge_damage[0] = 3.0
	state.edge_damage[1] = 7.0
	var events := BladeHitScan.scan(
			_held_pose(positions), state, hub.get_world_2d().direct_space_state, graph)

	var on_target := _events_on(events, target)
	assert_eq(on_target.size(), 1, "two overlapping capsules are still one contact")
	assert_true(on_target[0].is_edge_hit())
	assert_eq(on_target[0].edge_idx, 1, "the HIGHER-damage capsule is the one that counts")


# ── Acceptance 4: capsules add contact, not damage, until a sharpener ──────

func test_edge_damage_defaults_to_zero_on_the_stat_and_on_a_fresh_state() -> void:
	var def: StatDef = StatRegistry.get_def(&"edge_damage")
	assert_not_null(def, "edge_damage must be a registered StatDef")
	assert_eq(def.default_value, 0.0,
			"default 0 — an unsharpened blade's edges collide but deal nothing")

	var board: EntityStatBoard = _BOARD.duplicate(true)
	assert_eq(board.get_stat(&"edge_damage").get_value(), 0.0,
			"and the shipped entity board carries that 0, not blade_damage's 1")

	var state := BladeState.build(
			[Vector2.ZERO, Vector2(100.0, 0.0)], 0, [Vector2i(0, 1)], [10.0, 10.0])
	assert_eq(state.edge_damage.size(), 1, "one slot per edge")
	assert_eq(state.edge_damage[0], 0.0, "zero-init, like vertex_damage")


func test_an_unsharpened_edge_contact_lands_nothing() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn(graph, "Arm", Vector2(400.0, 0.0))
	var target := _spawn(graph, "Target", Vector2(200.0, 0.0))
	await _settle()

	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(400.0, 0.0)]
	var state := BladeState.build(
			positions, 0, [Vector2i(0, 1)], [pivot.radius, arm.radius])
	var events := BladeHitScan.scan(
			_held_pose(positions), state, pivot.get_world_2d().direct_space_state, graph)
	var on_target := _events_on(events, target)
	assert_eq(on_target.size(), 1, "the contact still happens")

	var di := DamageInstance.new()
	di.amount = state.edge_damage[on_target[0].edge_idx]
	di.type = DamageInstance.Type.PHYSICAL
	assert_eq(Mitigation.apply(di, target), 0.0,
			"a zero-coefficient contact lands zero — the min_damage_taken floor "
			+ "only triggers on a real hit, so capsules add contact, not damage")


# ── Acceptance 5: a capsule spends spikes exactly as a vertex does ─────────

class _SpikeFixture extends RefCounted:
	var graph: Graph
	var attacker: Entity
	var defender: Entity
	var spiked: SkillNode
	var state: BladeState
	var gate: BladePopResolver.LiveGate


func _spike_fixture(spike_power: float) -> _SpikeFixture:
	var f := _SpikeFixture.new()
	f.graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(f.graph)
	f.attacker = autofree(Entity.new())
	f.attacker.stat_board = _BOARD.duplicate(true)
	f.graph.add_child(f.attacker)
	f.defender = autofree(Entity.new())
	f.defender.stat_board = _BOARD.duplicate(true)
	var camp := Faction.new()
	camp.id = &"edge_collision_enemy"
	f.defender.faction = camp
	f.graph.add_child(f.defender)

	f.spiked = _spawn(f.graph, "Spiked", Vector2(200.0, 0.0))
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = f.graph
	add_child_autofree(alloc)
	alloc.force_allocate(f.defender, f.spiked)

	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	spike.local_modifiers = [mod]
	f.spiked.add_child(spike)
	await get_tree().process_frame

	var pool := f.spiked.node_board.get_stat(&"spikes") as PoolStat
	assert_not_null(pool, "fixture assumption: SpikeRingAddon mints a spikes pool")
	pool.set_current(spike_power)

	# Pivot ── Arm, with the spiked node parked mid-segment (the straddle pose).
	f.state = BladeState.build(
			[Vector2.ZERO, Vector2(400.0, 0.0)], 0, [Vector2i(0, 1)], [20.0, 20.0])
	f.gate = BladePopResolver.LiveGate.new(f.state, f.attacker)
	return f


func test_an_edge_contact_that_fully_drains_the_pool_severs_the_edge() -> void:
	var f: _SpikeFixture = await _spike_fixture(4.0)
	var pool := f.spiked.node_board.get_stat(&"spikes") as PoolStat
	var before := pool.current

	var admitted := f.gate.admit(
			BladeHitEvent.new(0.3, -1, 0, f.spiked), CombatWorld.live())

	assert_false(admitted, "the popping contact itself deals no damage — as for a vertex")
	assert_lt(pool.current, before, "the capsule spent the defender's spikes")
	assert_true(f.state.is_edge_removed(0), "and the EDGE is what broke, not a vertex")
	assert_eq(f.gate.result.severed_at.get(0), 0.3, "severance is recorded at contact time")
	assert_eq(f.gate.result.dead_at.get(1), 0.3,
			"the arm hung off that edge alone, so it disintegrates with it")
	var pop := f.gate.last_pop()
	assert_not_null(pop, "a severance is a pop record, so the cue reaches the replay")
	assert_eq(pop.edge_idx, 0)
	assert_eq(pop.particle_idx, -1, "exactly one of the two is set, per BladeHitEvent's rule")


func test_an_edge_contact_that_cannot_fully_drain_passes_through_instead() -> void:
	# "Pop only if full amount is removed" (#778) applies unchanged to an edge:
	# a remainder below the edge's blunting drains to 0 and lets the contact
	# land as an ordinary hit.
	var f: _SpikeFixture = await _spike_fixture(0.25)
	var pool := f.spiked.node_board.get_stat(&"spikes") as PoolStat

	var admitted := f.gate.admit(
			BladeHitEvent.new(0.3, -1, 0, f.spiked), CombatWorld.live())

	assert_true(admitted, "a partial drain never pops — the contact goes through")
	assert_eq(pool.current, 0.0, "but it still empties what was left")
	assert_false(f.state.is_edge_removed(0), "and the edge survives")


func test_a_severed_edge_is_not_scanned_again() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn(graph, "Arm", Vector2(400.0, 0.0))
	var target := _spawn(graph, "Target", Vector2(200.0, 0.0))
	await _settle()

	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(400.0, 0.0)]
	var state := BladeState.build(
			positions, 0, [Vector2i(0, 1)], [pivot.radius, arm.radius])
	state.remove_edge(0)
	var events := BladeHitScan.scan(
			_held_pose(positions), state, pivot.get_world_2d().direct_space_state, graph)
	assert_eq(_events_on(events, target).size(), 0, "a gone edge collides with nothing")


# ── Acceptance 7: reachability learned about severed edges, still O(V + E) ─

## A path pivot=0 -1-2-3, with an extra chord 0-3 so severance, not vertex
## removal, is the only thing under test.
func _chain_state() -> BladeState:
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(100, 0), Vector2(200, 0), Vector2(300, 0)]
	return BladeState.build(
			positions, 0,
			[Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)],
			[10.0, 10.0, 10.0, 10.0])


func test_reachability_walks_every_edge_when_none_is_severed() -> void:
	var state := _chain_state()
	var reach := BladePopResolver._reachable_from_pivot(state, {})
	assert_eq(reach.keys().size(), 4, "an intact chain reaches all four vertices")


func test_severing_an_edge_orphans_everything_beyond_it() -> void:
	var state := _chain_state()
	state.remove_edge(1)  # the 1-2 link
	var reach := BladePopResolver._reachable_from_pivot(state, {})
	var got := reach.keys()
	got.sort()
	assert_eq(got, [0, 1],
			"cutting the 1-2 edge strands 2 and 3, exactly as popping vertex 2 would")


func test_removing_an_edge_drops_its_distance_constraint_but_not_a_brace() -> void:
	var state := _chain_state()
	var brace := BladeDistanceConstraint.new(0, 3, 300.0)
	state.constraints.append(brace)
	assert_eq(state.constraints.size(), 4)

	assert_true(state.remove_edge(1), "first removal reports that it did the work")
	assert_false(state.remove_edge(1), "and it is idempotent")
	assert_eq(state.constraints.size(), 3, "the 1-2 distance constraint went with it")
	assert_true(state.constraints.has(brace),
			"a phantom brace is not an edge and must survive")
	assert_eq(state.edges.size(), 3,
			"`edges` is never spliced — an edge_idx on a pending event must stay valid")


## Acceptance 7's real claim: gaining edge-removal support must not reintroduce
## a rescan. The adjacency map carries the edge index alongside each neighbour,
## so the BFS skips a severed edge in O(1) as it walks — and because severance
## is a set rather than a splice, the map built once at the top of the swing is
## still correct afterwards and is NOT rebuilt.
func test_severance_does_not_rebuild_the_cached_adjacency_map() -> void:
	var f: _SpikeFixture = await _spike_fixture(4.0)
	f.gate.admit(BladeHitEvent.new(0.3, -1, 0, f.spiked), CombatWorld.live())

	assert_true(f.gate._adjacency_built, "the swing's one map is still the live one")
	var links: Array = f.gate._adjacency.get(0, [])
	assert_eq(links.size(), 1,
			"the severed edge was NOT pruned out of the map — pruning is the rescan "
			+ "#795 removed; the BFS skips it by index instead")
	assert_eq((links[0] as Vector2i).y, 0, "each link carries its own edge index")


func test_adjacency_pairs_every_neighbour_with_its_edge_index() -> void:
	var state := _chain_state()
	var adj := BladePopResolver._build_adjacency(state)
	assert_eq(adj[0], [Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(adj[1], [Vector2i(0, 0), Vector2i(2, 1)] as Array[Vector2i],
			"neighbour order still matches a linear rescan of state.edges (#795)")
	assert_eq(adj[3], [Vector2i(2, 2)] as Array[Vector2i])
