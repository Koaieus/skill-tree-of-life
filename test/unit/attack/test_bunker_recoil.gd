extends GutTest

## #1634 — a Bunker member is heavy and recoils off a bunker plate: velocity-
## level restitution on bunker x bunker contact only; every other contact stays
## position-based and inelastic. A lone free disc flies into a plate with no
## edges and no drivers, so its velocity after contact is the contact's alone.
## Nothing here pins the knobs' literals — only the ratios they set.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/defs/bunker_addon.tscn")

const _PLATE_RADIUS := 32.0
const _DISC_RADIUS := 10.0
## Per-substep displacement toward the plate (the Verlet velocity).
const _APPROACH := 2.0
const _STEPS := 20


## Pivot far off (pinned, inert), particle 1 heading straight at a plate
## centred on the origin along -x. Returns its normal (+x) velocity, per
## substep, at the first and the last sample.
func _fly(restitution: float) -> Dictionary:
	var positions: Array[Vector2] = [Vector2(-2000.0, 0.0), Vector2(80.0, 0.0)]
	var radii: Array[float] = [_DISC_RADIUS, _DISC_RADIUS]
	var state := BladeState.build(positions, 0, [] as Array[Vector2i], radii)
	state.vertex_restitution[1] = restitution
	state.prev_positions = state.positions.duplicate()
	state.prev_positions[1] = state.positions[1] + Vector2(_APPROACH, 0.0)
	var field := BladeObstacleField.new()
	field.add_zone(Vector2.ZERO, _PLATE_RADIUS)
	state.obstacles = field
	# step_offset 1: a continued chunk, so the sim keeps the seeded history.
	var traj := BladeSim.simulate_range(state, [] as Array[BladeDriver], 1, _STEPS)
	assert_not_null(traj, "the native solver ran the swing")
	var last := traj.samples.size() - 1
	return {
		approach = (traj.samples[1][1] - traj.prev_samples[1][1]).x,
		leave = (traj.samples[last][1] - traj.prev_samples[last][1]).x,
		x = traj.samples[last][1].x,
	}


func test_a_bunker_member_rebounds_off_a_plate_at_restitution_times_approach() -> void:
	var r := _fly(0.5)
	assert_almost_eq(r.approach, -_APPROACH, 0.01, "it was approaching before contact")
	assert_almost_eq(r.leave, 0.5 * _APPROACH, 0.1,
			"it leaves along the normal at restitution x the approach speed")


func test_an_inelastic_member_does_not_rebound() -> void:
	var r := _fly(0.0)
	assert_almost_eq(r.leave, 0.0, 0.05, "a plain vertex stops on the plate, no recoil")
	assert_almost_eq(r.x, _PLATE_RADIUS + _DISC_RADIUS, 1.0, "and rests against it")


## source - plain - bunker; selection order -> particles 0 (pivot), 1, 2.
func test_a_bunker_members_inverse_mass_is_half_a_plain_members() -> void:
	var graph := TestWorld.create(self).graph
	var alloc := TestWorld.allocator_for(graph)
	var entity := Entity.new()
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(entity)
	var nodes: Array[SkillNode] = []
	for nm in ["Source", "Plain", "Bunkered"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = nm
		graph.add_skill_node(sn)
		nodes.append(sn)
	graph.add_edge(nodes[0], nodes[1])
	graph.add_edge(nodes[1], nodes[2])
	await get_tree().process_frame
	for sn in nodes:
		alloc.force_allocate(entity, sn)
	var bunker := _BUNKER_SCENE.instantiate() as SkillNodeAddon
	nodes[2].add_child(bunker)
	await get_tree().process_frame

	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = entity
	plan.source = nodes[0]
	var members: Array[SkillNode] = [nodes[1], nodes[2]]
	plan.blade_nodes = members
	var state := plan.build_blade_state()
	assert_eq(state.inv_masses[0], 0.0, "the pivot stays pinned")
	assert_almost_eq(state.inv_masses[2], state.inv_masses[1] * 0.5, 1e-6,
			"a bunker member is twice as heavy as a plain one")
	assert_gt(state.vertex_restitution[2], 0.0, "a bunker member recoils")
	assert_eq(state.vertex_restitution[1], 0.0, "a plain member does not")
