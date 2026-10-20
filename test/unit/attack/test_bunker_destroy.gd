extends GutTest

## #1634 — a bunker member hitting a bunker plate hard enough knocks the
## defender's Bunker off; below the threshold it is an elastic clang. Momentum
## is the PEAK, over the contact, of normal approach speed x member mass.
## The swing-level claims live in test/integration/test_bunker_destroy_replay.gd.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

const _PLATE_RADIUS := 32.0
const _DISC_RADIUS := 10.0
## Per-substep displacement toward the plate (the Verlet velocity).
const _APPROACH := 2.0
const _STEPS := 20


## A lone free disc flying into a plate; returns the field after the run.
func _fly(restitution: float, inv_mass: float = 1.0) -> BladeObstacleField:
	var positions: Array[Vector2] = [Vector2(-2000.0, 0.0), Vector2(80.0, 0.0)]
	var radii: Array[float] = [_DISC_RADIUS, _DISC_RADIUS]
	var state := BladeState.build(positions, 0, [] as Array[Vector2i], radii)
	state.vertex_restitution[1] = restitution
	state.inv_masses[1] = inv_mass
	state.prev_positions = state.positions.duplicate()
	state.prev_positions[1] = state.positions[1] + Vector2(_APPROACH, 0.0)
	var field := BladeObstacleField.new()
	field.add_zone(Vector2.ZERO, _PLATE_RADIUS)
	state.obstacles = field
	var traj := BladeSim.simulate_range(state, [] as Array[BladeDriver], 1, _STEPS)
	assert_not_null(traj, "the native solver ran the swing")
	return state.obstacles


func test_a_bunker_members_contact_banks_a_momentum_peak() -> void:
	assert_gt(_fly(0.5).impact_peak(0), 0.0, "a bunker member's contact banks its momentum")


func test_a_plain_members_contact_banks_nothing() -> void:
	assert_eq(_fly(0.0).impact_peak(0), 0.0, "only bunker x bunker contact is measured")


func test_the_peak_scales_with_the_members_mass() -> void:
	var light := _fly(0.5, 1.0).impact_peak(0)
	var heavy := _fly(0.5, 0.5).impact_peak(0)
	assert_gt(light, 0.0, "precondition: the light member made contact")
	assert_almost_eq(heavy, 2.0 * light, light * 1e-3, "twice the mass, twice the momentum")


func test_a_destroy_entry_survives_the_wire() -> void:
	var graph := TestWorld.create(self).graph
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.add_skill_node(sn)
	await get_tree().process_frame
	var hit := AddonDestroyInstance.new()
	hit.target = sn
	hit.structural_key = 0.5
	var outcome := AttackOutcome.new()
	outcome.hits.append(hit)
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, graph)))
	var rebuilt := AttackRecord.rebuild(wired, graph)
	assert_eq(rebuilt.hits.size(), 1, "one entry on the wire")
	if rebuilt.hits.size() == 1:
		assert_true(rebuilt.hits[0] is AddonDestroyInstance, "rebuilt as a destroy")
		assert_eq(rebuilt.hits[0].target, sn, "naming the same node")
