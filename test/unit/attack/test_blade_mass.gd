extends GutTest

## A blade particle's mass is its disc's area, normalised so SkillNode's
## default radius weighs 1 — see BladeState.MASS_REF_RADIUS.


func test_the_reference_radius_weighs_exactly_one() -> void:
	assert_eq(BladeState.inv_mass_for(BladeState.MASS_REF_RADIUS), 1.0,
			"an unstaked plain member keeps the unit mass the knobs were tuned against")


func test_mass_goes_as_the_square_of_the_radius() -> void:
	var r := BladeState.MASS_REF_RADIUS
	assert_almost_eq(BladeState.inv_mass_for(2.0 * r), 0.25, 1e-6, "twice the radius, four times the mass")
	assert_almost_eq(BladeState.inv_mass_for(0.5 * r), 4.0, 1e-6, "half the radius, a quarter of the mass")


func test_a_degenerate_radius_falls_back_to_unit_mass() -> void:
	assert_eq(BladeState.inv_mass_for(0.0), 1.0, "never a division by zero")


func test_build_pins_the_pivot_and_weighs_every_other_particle_by_its_radius() -> void:
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(80, 0), Vector2(160, 0)]
	var radii: Array[float] = [32.0, 50.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2)]
	var s := BladeState.build(positions, 0, edges, radii)
	assert_eq(s.inv_masses[0], 0.0, "the pivot is pinned whatever its size")
	assert_almost_eq(s.inv_masses[1], BladeState.inv_mass_for(50.0), 1e-6, "a stake-4 node")
	assert_almost_eq(s.inv_masses[2], BladeState.inv_mass_for(16.0), 1e-6, "a small node")


## The whole of what mass does to a constraint: a stretched edge closes by
## moving its light end further than its heavy end, in the inverse ratio of
## their masses.
func test_the_heavier_end_of_a_stretched_edge_yields_less() -> void:
	var positions: Array[Vector2] = [Vector2(-1000, 0), Vector2.ZERO, Vector2(100, 0)]
	var radii: Array[float] = [32.0, 64.0, 32.0]
	var edges: Array[Vector2i] = [Vector2i(1, 2)]
	var s := BladeState.build(positions, 0, edges, radii)
	var dc := BladeDistanceConstraint.new(1, 2, 50.0)
	var before := s.positions.duplicate()
	dc.project(s.positions, s.inv_masses)
	var heavy_moved := s.positions[1].distance_to(before[1])
	var light_moved := s.positions[2].distance_to(before[2])
	assert_almost_eq(s.positions[1].distance_to(s.positions[2]), 50.0, 1e-3, "rigid: one projection closes it")
	assert_almost_eq(light_moved, 4.0 * heavy_moved, 1e-3, "four times the mass, a quarter of the correction")
