extends GutTest

## Blade EDGES collide, as swept capsules (#785) — and, under [b]ADR 0005[/b],
## that is [b]all[/b] they do. [b]Nodes deal damage, edges give rigidity; spikes
## pop vertices, bunkers break edges.[/b]
##
## The defect edge collision exists to close is the [b]straddle[/b]: a truss
## blade slams into a bunker and the initial nodes pass either side of it — with
## vertex-only hitboxes it slips between them and only bites deeper in the
## sweep, "causing bounces and largely chaotic behavior" (owner, 2026-09-07). An
## edge capsule catches it on contact. Keeping a bunker out of the blade's
## interior is the whole reason edges got hit-scan.
##
## #785 also, briefly, gave edges an `edge_damage` stat and enrolled them in the
## spike system, both derived as the MIN of their endpoints'. ADR 0005 retired
## both, so half of the tests below pin an [b]absence[/b]: an edge sweeping over
## a spiked node drains nothing, severs nothing, and lands nothing. Those are
## worth more than what they replaced — the failure mode they guard against
## (blunting 0 makes `remaining >= blunting` trivially true, so every contact
## `deplete(0)`s and severs) is silent, and it is exactly what an obvious "just
## zero it out" implementation produces.
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
## vertex-only contact an obstacle sitting in the gap between two vertices was
## simply not there as far as the blade was concerned; now every offset along
## the segment connects. (For SPIKES this "spacing luck" is a non-issue — the
## owner retired it 2026-09-08, since a floppy multi-layer blade hits with
## something — but for a BUNKER the gap was the straddle defect itself.)
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
		var on_target := _events_on(events, target)
		assert_gt(on_target.size(), 0,
				"a target at x=%.0f along the segment must contact" % home.x)
		# The EDGE specifically has to be one of them — that is the span being
		# covered. Near either end a vertex disk also reaches, and since ADR 0005
		# deleted the per-substep arbitration both simply emit; the count is not
		# the claim, the coverage is.
		var by_edge := false
		for ev in on_target:
			if ev.is_edge_hit():
				by_edge = true
		assert_true(by_edge,
				"and the EDGE must be what reaches it at x=%.0f" % home.x)
		target.global_position = home
		await get_tree().physics_frame


# ── A hub deals vertex damage, not vertex + one per spoke ─────────────────

## Six spokes out of one hub, target sitting ON the hub. #785 capped this with a
## per-substep "highest-damage element wins" arbitration; ADR 0005 deleted that
## along with edge damage, so the cap is now carried entirely by [b]geometry[/b]
## — the capsules are trimmed back to the rim of each endpoint's own disk, and
## whatever they still touch carries no damage to add.
##
## The claim is therefore about DAMAGE, not about the raw event count: a
## degree-6 hub is worth one damaging contact, and it is the vertex's.
func test_a_target_on_a_hub_takes_one_damaging_contact_not_one_per_spoke() -> void:
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
	var events := BladeHitScan.scan(
			_held_pose(positions), state, hub.get_world_2d().direct_space_state, graph)

	var vertex_hits := 0
	for ev in _events_on(events, target):
		if not ev.is_edge_hit():
			vertex_hits += 1
			assert_eq(ev.particle_idx, 0, "the only vertex in range is the hub itself")
	assert_eq(vertex_hits, 1,
			"the hub is worth ONE damaging contact, not 1 + degree — the spokes' "
			+ "capsules start at its rim and carry no damage besides")


# ── Overlapping capsules: nothing to rank, because nothing carries damage ──

## Two edges splayed at a narrow angle off a shared hub, with a target just
## outside the hub's disk and inside BOTH capsules. #785 arbitrated this on
## `edge_damage` — the higher capsule won outright and the loser was suppressed.
## With edge damage gone there is no ranking left to do and no double-dip to
## prevent: both capsules contact, and both contribute zero.
##
## This is the test that pins WHY the arbitration could be deleted rather than
## tuned. Its whole job was to stop one contact being counted as vertex + edge
## damage, and an edge no longer has any damage to count.
func test_two_overlapping_capsules_contact_and_neither_carries_damage() -> void:
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
	var events := BladeHitScan.scan(
			_held_pose(positions), state, hub.get_world_2d().direct_space_state, graph)

	var on_target := _events_on(events, target)
	assert_eq(on_target.size(), 2,
			"both capsules contact — nothing suppresses the second one any more")
	var seen: Array[int] = []
	for ev in on_target:
		assert_true(ev.is_edge_hit(), "no vertex reaches this target")
		seen.append(ev.edge_idx)
	seen.sort()
	assert_eq(seen, [0, 1] as Array[int], "one contact per edge, deduped per collider")


# ── Edges carry no stats at all, and no damage ────────────────────────────

## The removal itself, pinned where it can rot loudly. `edge_damage` shipped on
## master for a day as a derived stat (the MIN of an edge's two endpoints');
## ADR 0005 struck it — a derivation would make triangulating for RIGIDITY
## silently multiply DAMAGE, collapsing "add a node for offence, add an edge for
## structure" into one decision.
func test_there_is_no_edge_damage_stat_and_no_per_edge_damage_array() -> void:
	assert_null(StatRegistry.get_def(&"edge_damage"),
			"ADR 0005: an edge carries no stats, so no `edge_damage` StatDef exists")

	var board: EntityStatBoard = _BOARD.duplicate(true)
	assert_null(board.get_stat(&"edge_damage"),
			"and the shipped entity board has no slot for one")

	var state := BladeState.build(
			[Vector2.ZERO, Vector2(100.0, 0.0)], 0, [Vector2i(0, 1)], [10.0, 10.0])
	assert_false(&"edge_damage" in state,
			"nor does BladeState carry a per-edge damage array to fill")
	assert_eq(state.vertex_damage.size(), 2,
			"the per-VERTEX array survives untouched — nodes are what deal damage")


func test_an_edge_contact_lands_no_damage_at_all() -> void:
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
	assert_eq(on_target.size(), 1, "the contact still happens — that is the point")
	assert_true(on_target[0].is_edge_hit())

	# What MeleeAttackPlan.resolve_against stamps for an edge event: a flat 0,
	# with no coefficient to look up anywhere.
	var di := DamageInstance.new()
	di.amount = 0.0
	di.type = DamageInstance.Type.PHYSICAL
	assert_eq(Mitigation.apply(di, target), 0.0,
			"a zero-amount contact lands zero — the min_damage_taken floor only "
			+ "triggers on a real hit, so capsules add contact, not damage")


# ── An edge NEVER interacts with spikes (ADR 0005) ────────────────────────

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


## The headline absence. Before ADR 0005 this same contact drained the pool and
## severed the edge; now it does neither. A spike destroys matter, a bunker
## destroys structure — an edge is structure, and a spike ring has no purchase
## on it.
func test_an_edge_over_a_spiked_node_drains_nothing_and_severs_nothing() -> void:
	var f: _SpikeFixture = await _spike_fixture(4.0)
	var pool := f.spiked.node_board.get_stat(&"spikes") as PoolStat
	var before := pool.current

	var admitted := f.gate.admit(
			BladeHitEvent.new(0.3, -1, 0, f.spiked), CombatWorld.live())

	assert_true(admitted, "the contact is admitted — it just carries no damage")
	assert_eq(pool.current, before, "the defender's spikes are untouched")
	assert_false(f.state.is_edge_removed(0), "and the edge is intact")
	assert_eq(f.gate.result.severed_at.size(), 0, "nothing was recorded as severed")
	assert_eq(f.gate.result.dead_at.size(), 0,
			"so nothing was orphaned either — the arm still hangs off a live edge")
	assert_eq(f.gate.result.pops.size(), 0, "and no Pop was minted")
	assert_null(f.gate.last_pop(), "so the replay gets no pop cue from an edge")


## The inverted-#778 trap, pinned. Expressing "edges do not blunt" as
## `_blunting_for_edge() -> 0.0` would make `remaining >= blunting` trivially
## true, so a nearly-empty pool would `deplete(0)` and SEVER — quietly turning
## every edge contact into a guaranteed break. A pool this small is where that
## bug shows up first, so this is where it is nailed down.
func test_an_edge_does_not_even_drain_a_nearly_empty_spike_pool() -> void:
	var f: _SpikeFixture = await _spike_fixture(0.25)
	var pool := f.spiked.node_board.get_stat(&"spikes") as PoolStat

	var admitted := f.gate.admit(
			BladeHitEvent.new(0.3, -1, 0, f.spiked), CombatWorld.live())

	assert_true(admitted, "still admitted")
	assert_eq(pool.current, 0.25, "0.25 left is 0.25 left — an edge drains nothing")
	assert_false(f.state.is_edge_removed(0),
			"and above all it does NOT sever, which a blunting-0 ladder would")


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
	# Driven straight at the seam: since ADR 0005 no spike drain severs an edge,
	# so `_sever_edge` has no production caller until #781's bunker lands. The
	# invariant it must keep is the same either way — #795's one adjacency build
	# per swing has to survive an edge going away mid-swing.
	f.gate._ensure_adjacency()
	f.gate._sever_edge(0, 0.3, f.spiked, 0.0)

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
