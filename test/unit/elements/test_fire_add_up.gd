extends GutTest

## Fire's add-up on [DiscGoOff]: [method DiscGoOff.shape_disc_radius] (A × (√shape
## + √excess + B) × the origin's radius) and [method DiscGoOff.fire_shaped_in],
## the one combined disc a shape and a Burning node make (ADR 0084 §3), which
## spends the node's solo cost (ADR 0084 §4), its [member GoOff.void_floor]
## added (ADR 0097 §4); on a node that is
## not Burning the shape runs alone and spends nothing.
##
## A bare instance throughout, so knob writes never leak into Fire's shared def.
## The centre is grown to 1.5× every other node's radius, so a radius read off
## any other node misplaces the disc. A node is reached when its hitbox touches
## the disc: an "inside" node's hitbox sits 0.1 r inside the radius, an
## "outside" one 0.1 r past it.

## Each centre's anchor sits this far west of it: outside any disc.
const _FAR := 20000.0
const _GROW := 1.5

var _w: TestWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.reset_live()


func _element(id: StringName) -> Element:
	return ElementRoster.shared().by_id(id)


func _read(node: SkillNode) -> TerrainRead:
	return TerrainRead.of(node.get_combat(), node)


func _reached(result: GoOffResult) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for r in result.reached:
		out.append(r.node)
	return out


## The centre: at the origin, grown to [constant _GROW]× the default radius,
## linked to a far anchor (degree 1, so T > 0) and allocated.
func _centre() -> SkillNode:
	var c := _w.add_node(&"C")
	c.base_radius *= _GROW
	c.global_position = Vector2.ZERO
	var anchor := _w.add_node(&"C_anchor")
	anchor.global_position = Vector2(-_FAR, 0.0)
	_w.link(c, anchor)
	_w.allocate(_w.add_entity("Red"), [c])
	return c


## A node whose hitbox sits [param edge] px from [param from]'s centre, at
## [param angle] (radians, 0 = due east).
func _at(from: SkillNode, id: StringName, edge: float, angle := 0.0) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = from.global_position + Vector2.from_angle(angle) * (edge + n.radius)
	return n


## [param n]'s Heat set to its T + [param excess].
func _prime(n: SkillNode, excess: int) -> void:
	var c := n.get_combat()
	c.add_terrain(_element(&"fire"), c.terrain_threshold() + excess - c.terrain_t())


# --- 1: the radius ----------------------------------------------------------------

func test_shape_disc_radius_adds_the_roots_and_shape_zero_is_the_disc() -> void:
	var disc := DiscGoOff.new()
	for knobs: Array in [[disc.radius_a, disc.radius_b], [3.0, 0.5]]:
		disc.radius_a = knobs[0]
		disc.radius_b = knobs[1]
		var a := disc.radius_a
		var b := disc.radius_b
		for e: float in [1.0, 4.0]:
			assert_almost_eq(disc.shape_disc_radius(0.0, e, 40.0), disc.disc_radius(e, 40.0), 0.0001,
					"shape 0 is the disc at excess %s (A %s, B %s)" % [e, a, b])
		for se: Array in [[15.0, 4.0], [9.0, 1.0]]:
			var s: float = se[0]
			var e: float = se[1]
			var want := a * (sqrt(s) + sqrt(e) + b) * 40.0
			assert_almost_eq(disc.shape_disc_radius(s, e, 40.0), want, 0.0001,
					"A × (√%s + √%s + B) × R (A %s, B %s)" % [s, e, a, b])
			assert_almost_eq(disc.shape_disc_radius(s, e, 80.0), 2.0 * want, 0.0001,
					"doubling R doubles it (A %s, B %s)" % [a, b])


# --- 2: combined ------------------------------------------------------------------

func test_a_burning_node_shaped_reaches_the_combined_disc_and_pays_its_solo_cost() -> void:
	var disc := DiscGoOff.new()
	var c := _centre()
	var r_big := c.radius
	var solo := disc.disc_radius(4, r_big)
	var combined := disc.shape_disc_radius(15.0, 4.0, r_big)
	var s1 := _at(c, &"S1", 0.3 * solo)
	var r := s1.radius
	var s2 := _at(c, &"S2", 0.5 * solo, PI / 2.0)
	var inside := _at(c, &"In", combined - 0.1 * r)
	var outside := _at(c, &"Out", combined + 0.1 * r)
	assert_almost_eq(r_big, _GROW * r, 0.001, "fixture: the centre's radius is unlike the others'")
	assert_gt(combined - 0.1 * r, solo, "fixture: In sits outside the solo disc")
	await get_tree().process_frame
	_prime(c, 4)
	var result := disc.fire_shaped_in(null, c, _read(c), 15.0)
	var reached := _reached(result)
	assert_true(reached.has(inside), "the node just inside the combined disc is reached")
	assert_false(reached.has(outside), "the one just outside is not")
	assert_true(reached.has(s1) and reached.has(s2), "the solo disc's nodes are reached")
	assert_false(reached.has(c), "never the centre")
	var solo_spend := disc.fire_in(null, c, _read(c)).spend()
	assert_eq(solo_spend, 2 + disc.void_floor, "fixture: the solo disc holds S1 and S2, plus the floor")
	assert_eq(result.spend(), solo_spend, "the node pays what its own disc spends")
	assert_lt(result.spend() - result.nodeless_cost, reached.size(), "not 1 per node reached")
	assert_false(result.cost.has(inside), "a node past the solo disc costs nothing")
	assert_eq(result.nodeless_cost, disc.void_floor, "the floor is added, never a max")
	assert_eq(result.power, 4, "power is the node's excess")
	assert_almost_eq(result.reach, combined, 0.001, "reach is the combined radius")
	assert_almost_eq(result.own_damage, disc.damage_per_power * 4, 0.0001, "own damage reads the excess only")
	assert_almost_eq(result.share, disc.share, 0.0001, "the copies ride the disc's share")


# --- 3: the floor -----------------------------------------------------------------

func test_a_solo_disc_reaching_nobody_pays_the_floor_inside_a_reaching_combined_disc() -> void:
	var disc := DiscGoOff.new()
	var c := _centre()
	var solo := disc.disc_radius(1, c.radius)
	var combined := disc.shape_disc_radius(4.0, 1.0, c.radius)
	var n := _at(c, &"N", 0.5 * (solo + combined))
	await get_tree().process_frame
	_prime(c, 1)
	assert_true(disc.fire_in(null, c, _read(c)).reached.is_empty(), "fixture: the solo disc reaches nobody")
	var result := disc.fire_shaped_in(null, c, _read(c), 4.0)
	assert_eq(_reached(result), [n], "the combined disc reaches N")
	assert_eq(result.spend(), disc.void_floor, "the node pays the floor")
	assert_eq(result.spend(), 1, "the floor defaults to 1")
	disc.void_floor = 0
	assert_eq(disc.fire_shaped_in(null, c, _read(c), 4.0).spend(), 0, "floor 0 turns it off")


func test_a_combined_disc_reaching_nobody_is_empty_and_voids_only_its_floor() -> void:
	var disc := DiscGoOff.new()
	var c := _centre()
	await get_tree().process_frame
	_prime(c, 1)
	var result := disc.fire_shaped_in(null, c, _read(c), 4.0)
	assert_true(result.reached.is_empty(), "nobody in the combined disc")
	assert_eq(result.spend(), disc.void_floor, "only the floor (floor_when_unreached)")
	disc.floor_when_unreached = false
	assert_eq(disc.fire_shaped_in(null, c, _read(c), 4.0).spend(), 0, "off: no spend")


# --- 4: alone ---------------------------------------------------------------------

func _assert_alone(disc: DiscGoOff, c: SkillNode, inside: SkillNode, outside: SkillNode, label: String) -> void:
	var result := disc.fire_shaped_in(null, c, _read(c), 9.0)
	var reached := _reached(result)
	assert_true(reached.has(inside), "%s: the shape alone reaches the node inside it" % label)
	assert_false(reached.has(outside), "%s: not the one past it" % label)
	assert_eq(result.spend(), 0, "%s: no spend" % label)
	assert_almost_eq(result.own_damage, 0.0, 0.0001, "%s: no own damage" % label)
	assert_eq(result.power, 0, "%s: no power" % label)
	assert_almost_eq(result.reach, disc.shape_disc_radius(9.0, 0.0, c.radius), 0.001, "%s: reach is the shape's" % label)


func test_on_a_node_at_t_the_shape_runs_alone() -> void:
	var disc := DiscGoOff.new()
	var c := _centre()
	var alone := disc.shape_disc_radius(9.0, 0.0, c.radius)
	var inside := _at(c, &"In", alone - 3.2)
	var outside := _at(c, &"Out", alone + 3.2)
	await get_tree().process_frame
	_prime(c, 0)
	assert_eq(disc.power_at(c, _read(c)), 0, "fixture: Heat at T is not Burning")
	_assert_alone(disc, c, inside, outside, "Heat at T")
	var none := disc.fire_shaped_in(null, c, _read(c), 0.0)
	assert_true(none.reached.is_empty(), "no shape and no excess is no go-off")
	assert_eq(none.spend(), 0, "and spends nothing")


func test_on_a_frozen_node_the_shape_runs_alone() -> void:
	var disc := DiscGoOff.new()
	var c := _centre()
	var alone := disc.shape_disc_radius(9.0, 0.0, c.radius)
	var inside := _at(c, &"In", alone - 3.2)
	var outside := _at(c, &"Out", alone + 3.2)
	await get_tree().process_frame
	var combat := c.get_combat()
	combat.add_terrain(_element(&"ice"), combat.terrain_threshold() + 1)
	assert_lt(combat.terrain_t(), -combat.terrain_threshold(), "fixture: Cold past T, the node is Frozen")
	_assert_alone(disc, c, inside, outside, "Frozen")
