extends GutTest

## #811 / #808 — a whipped blade reaches far past its REST pose, and the
## defenders in that annulus must defend.
##
## [b]The fixture is the bug.[/b] A 5-node W blade at
## `(0,0) (100,150) (200,0) (300,150) (400,0)`, pivot at the top-left end, has a
## rest reach of 432 px (400 px to the far end plus that node's 32 px radius) —
## which is exactly what the deleted `MeleeAttackPlan._blade_reach` bounded the
## zone builds by. Swinging it straightens it: the chain is 4 x 180.28 = 721.1 px
## long, and the tip was measured whipping out to 714.6 px, 65% past the cull.
## Every fortified or bunkered node in that annulus silently failed to drag or
## deflect while [BladeHitScan], which senses off the LIVE pose, damaged them
## normally.
##
## Both tests below place their defender on a point the free swing's tip
## actually passes through, read off its own trajectory and asserted to be
## outside the old cull — the same trick `test_bunker_break_live.gd` uses for
## its floppy plate, and the reason neither test hard-codes a position: deriving
## it means simulating the swing that the obstacle then changes.
##
## Both fail on master: there the node is culled out of the zone build, so the
## clock never warps and the field is never allocated.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")

## The W, exactly as #811's acceptance 1 specifies it. Pivot is index 0.
const _W: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(100.0, 150.0), Vector2(200.0, 0.0),
	Vector2(300.0, 150.0), Vector2(400.0, 0.0),
]

## The rest reach the deleted cull used: |pivot - far end| + that node's radius.
const _REST_REACH := 432.0

## Where on the tip's own path the defender is parked: the first sample whose
## distance from the pivot clears this. Comfortably outside `_REST_REACH` + a
## node radius, so master's cull cannot reach it by accident.
const _ANNULUS_FLOOR := 520.0

const _TIP_IDX := 4


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity(graph: Graph) -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	graph.add_child(entity)
	return entity


## The W blade on a fresh graph, plus one hostile node parked far away. The
## caller moves that node onto the whip path once it has measured one.
func _setup() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var camp := Faction.new()
	camp.id = &"whip_reach_enemy"
	defender.faction = camp

	var members: Array[SkillNode] = []
	for i in _W.size():
		members.append(_spawn(graph, "W%d" % i, _W[i]))
	for i in range(1, members.size()):
		graph.add_edge(members[i - 1], members[i])
	# Parked off the map; the test moves it onto the measured whip path.
	var hostile := _spawn(graph, "Hostile", Vector2(100000.0, 100000.0))

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	for sn in members:
		alloc.force_allocate(attacker, sn)
	attacker.core_location = members[0]
	alloc.force_allocate(defender, hostile)
	defender.core_location = hostile

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = members[0]
	plan.blade_nodes = members.slice(1)
	return {"graph": graph, "plan": plan, "hostile": hostile, "members": members}


## Simulate the UNDEFENDED swing and hand back the first tip sample past
## [constant _ANNULUS_FLOOR], plus the whole free trajectory to compare against.
func _whip_point(plan: MeleeAttackPlan) -> Dictionary:
	var state := plan.build_blade_state()
	assert_null(state.obstacles, "fixture: nothing defends yet")
	var traj := BladeSim.simulate(
			state, plan.build_drivers(state), MeleeAttackPlan.SWING_DURATION)
	var pivot := state.positions[state.pivot_index]
	var farthest := 0.0
	var chosen := Vector2.INF
	for sample in traj.samples:
		var d := pivot.distance_to(sample[_TIP_IDX])
		farthest = maxf(farthest, d)
		if chosen == Vector2.INF and d >= _ANNULUS_FLOOR:
			chosen = sample[_TIP_IDX]
	return {"point": chosen, "farthest": farthest, "traj": traj}


func test_the_w_blade_whips_far_past_its_rest_reach() -> void:
	# #808's measurement, re-derived by the fixture rather than pasted in: the
	# cull that both deleted zone builds used is 65% short of the truth.
	var ctx: Dictionary = await _setup()
	var whip: Dictionary = _whip_point(ctx.plan)
	assert_gt(float(whip.farthest), _REST_REACH,
			"a whipped W blade must reach past its rest reach — that IS the bug")
	assert_gt(float(whip.farthest), 700.0,
			"and it reaches ~714.6 px, not 432")
	assert_ne(whip.point, Vector2.INF,
			"fixture: the tip must pass through the annulus the test parks in")


func test_a_fortified_node_outside_the_rest_reach_still_drags_the_swing() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var hostile: SkillNode = ctx.hostile
	var whip: Dictionary = _whip_point(plan)

	hostile.global_position = whip.point
	hostile.add_child(_FORTIFICATION_SCENE.instantiate() as SkillNodeAddon)
	# An Area2D is not in the physics space until a physics frame runs — without
	# this the defender query comes back empty and this test silently passes
	# nothing.
	await get_tree().process_frame
	await get_tree().physics_frame

	var pivot: Vector2 = _W[0]
	assert_gt(pivot.distance_to(hostile.global_position), _REST_REACH + hostile.radius,
			"fixture: the wall must sit OUTSIDE the deleted cull, or this proves nothing")
	assert_gt(float(hostile.get_local_value(&"swing_drag")), 0.0,
			"fixture: Fortification must actually author swing_drag")

	plan._invalidate_prediction()
	plan.refresh_prediction()
	var result: MeleeAttackPlan.SwingResult = plan.prediction()
	assert_not_null(result.clock, "a defender in the whip annulus must build a clock")
	assert_true(result.clock.is_warping(),
			"the swing must actually contact the wall and start warping — on "
			+ "master the node is culled out of the build and never seen")
	assert_gt(result.clock.drag, 0.0, "and bank its drag")


func test_a_bunker_outside_the_rest_reach_still_deflects_the_swing() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var hostile: SkillNode = ctx.hostile
	var whip: Dictionary = _whip_point(plan)
	var free_traj: BladeTrajectory = whip.traj

	hostile.global_position = whip.point
	hostile.add_child(_BUNKER_SCENE.instantiate() as SkillNodeAddon)
	await get_tree().process_frame
	await get_tree().physics_frame

	assert_true(bool(hostile.get_local_value(&"deflection")),
			"fixture: Bunker must actually author deflection")

	var state := plan.build_blade_state()
	assert_not_null(state.obstacles,
			"a bunker in the whip annulus must attach a field — on master the "
			+ "rest-pose cull drops it and no field is ever allocated")
	assert_eq(state.obstacles.zones.size(), 1, "exactly one zone for one plate")
	assert_true(state.obstacles.zones.deflects_at(0), "and it is a PLATE, not a wall")

	var deflected := BladeSim.simulate(
			state, plan.build_drivers(state), MeleeAttackPlan.SWING_DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, true,
			BladeSwingClock.new(MeleeAttackPlan.SWING_DURATION))
	var moved := false
	for i in mini(free_traj.samples.size(), deflected.samples.size()):
		if free_traj.samples[i] != deflected.samples[i]:
			moved = true
			break
	assert_true(moved,
			"the plate must push the blade off its free path — an identical "
			+ "trajectory means the pushout never ran")


func test_a_node_carrying_both_stats_is_one_zone_of_both_kinds() -> void:
	# The merge's own asymmetry (#811): `deflection` is a bool, `swing_drag` a
	# magnitude, and a node with both is ONE entry, never two — the drag latch
	# keys on the zone index, so a doubled zone would double its wall.
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var hostile: SkillNode = ctx.hostile
	var whip: Dictionary = _whip_point(plan)

	hostile.global_position = whip.point
	hostile.add_child(_FORTIFICATION_SCENE.instantiate() as SkillNodeAddon)
	hostile.add_child(_BUNKER_SCENE.instantiate() as SkillNodeAddon)
	await get_tree().process_frame
	await get_tree().physics_frame

	var state := plan.build_blade_state()
	assert_not_null(state.obstacles, "both stats in reach must attach a field")
	var zones: BladeDefenderZones = state.obstacles.zones
	assert_eq(zones.size(), 1, "one node is one zone, however many stats it carries")
	assert_true(zones.deflects_at(0), "the zone is a plate")
	assert_gt(zones.drags[0], 0.0, "and a wall")
	assert_true(zones.has_drag() and zones.has_deflection(),
			"the set reports both kinds present")


# ── Zone ORDER is defined, because intersect_shape's is not ─────────────────

## [method PhysicsDirectSpaceState2D.intersect_shape] returns colliders in
## broadphase order — undefined, and not reproducible across machines. Two
## first-wins tie-breaks read the zone order (which zone seeds
## [member BladeSwingClock._warping], and which arms a break first), so #811
## sorts by [member SkillNode.stable_id] and pins that here. Without the sort
## this is the kind of bug that shows up as a desync, not as a red test.
func test_the_zone_set_is_ordered_by_stable_id_and_reproduces() -> void:
	var ctx: Dictionary = await _setup()
	var plan: MeleeAttackPlan = ctx.plan
	var graph: Graph = ctx.graph
	var defender: Entity = _make_entity(graph)
	var camp := Faction.new()
	camp.id = &"whip_reach_order_enemy"
	defender.faction = camp
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)

	# Ring the pivot with walls, spawned in an order that has nothing to do with
	# their positions, so a position-ordered broadphase cannot accidentally
	# agree with stable_id order.
	var walls: Array[SkillNode] = []
	for i in 6:
		var a := (0.37 * float((i * 5) % 6)) * TAU
		var sn := _spawn(graph, "Wall%d" % i, Vector2.from_angle(a) * 300.0)
		sn.add_child(_FORTIFICATION_SCENE.instantiate() as SkillNodeAddon)
		walls.append(sn)
	await get_tree().process_frame
	for sn in walls:
		alloc.force_allocate(defender, sn)
	defender.core_location = walls[0]
	await get_tree().process_frame
	await get_tree().physics_frame

	var first := plan.build_blade_state()
	assert_not_null(first.obstacles, "fixture: six walls must build a field")
	var zones: BladeDefenderZones = first.obstacles.zones
	assert_eq(zones.size(), walls.size(), "every wall must be found")
	var prev := -1
	for sn in zones.defenders:
		var id := graph.get_stable_id(sn)
		assert_gt(id, prev, "zones must be strictly ascending by stable_id")
		prev = id

	plan._invalidate_prediction()
	var second := plan.build_blade_state()
	assert_eq(second.obstacles.zones.centers, zones.centers,
			"the same query must reproduce the same zone order, every time")
	assert_eq(second.obstacles.zones.drags, zones.drags,
			"and the same per-zone magnitudes, in the same slots")
