extends GutTest

## [ReadoutLines]: one line per aspect in play — socketed first, in socket
## order, then innate-only — whose numbers are the plan's own
## ([method Infusion.load_of] through [method StatusDef.stacks_per_hit]).

const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
const _POISON_STATUS: StatusDef = preload("res://effects/status/poison.tres")
const _HEAT: StatusDef = preload("res://effects/status/heat.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## INT 100 → 1 infusion slot; every aspect zeroed but poison, which holds [param poison].
func _caster(poison: float) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = 100.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.facet(&"poison", StatDef.Role.COUNT).base_value = poison
	return atk


func _plan(caster: Entity) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = caster
	# Uncapped: these pins read every point a held aspect fills, past any cap.
	var spell := _VENOM.duplicate() as SpellDef
	spell.infusion_capacity = INF
	plan.set_spell(spell)
	return plan


func test_venom_with_40_poison_socketed_reads_innate_plus_infused() -> void:
	var caster := _caster(40.0)
	var plan := _plan(caster)
	plan.set_socket(0, &"poison")
	assert_eq(plan.infusion.points.get(&"poison", 0), 40, "guard: 40 points socketed")
	var aff: AspectIntake = _VENOM.intakes[0]
	assert_eq(aff.innate, 15, "guard: venom's innate poison")
	assert_eq(Vector2i(aff.affinity_gain, aff.affinity_cost), Vector2i(2, 1), "guard: venom's poison affinity")
	var lines := ReadoutLines.lines(plan)
	assert_eq(lines.size(), 1, "one aspect in play")
	if lines.size() != 1:
		return
	var line := lines[0]
	assert_eq(line.aspect_id, &"poison")
	assert_eq(line.socket, 0)
	assert_eq(line.points, 40)
	assert_eq(line.innate, 15)
	assert_eq(line.infused, 80)
	assert_eq(line.innate + line.infused, plan.infusion.load_of(_VENOM)[&"poison"],
			"the total is the plan's own load")
	assert_eq(line.per_hit, _POISON_STATUS.stacks_per_hit(caster.stat_board, 95.0),
			"per hit folds through stacks_per_hit")
	assert_eq(line.status, _POISON_STATUS)


func test_an_innate_only_aspect_yields_a_line_with_no_socket() -> void:
	var caster := _caster(0.0)
	var plan := _plan(caster)
	var lines := ReadoutLines.lines(plan)
	assert_eq(lines.size(), 1, "venom's innate poison is in play with nothing socketed")
	if lines.size() != 1:
		return
	assert_eq(lines[0].socket, -1)
	assert_eq(lines[0].innate, 15)
	assert_eq(lines[0].infused, 0)
	assert_eq(lines[0].points, 0)


func test_previewing_a_socket_reads_the_plan_as_if_socketed() -> void:
	var caster := _caster(40.0)
	var plan := _plan(caster)
	var preview := ReadoutLines.preview(plan, 0, &"poison")
	assert_eq(plan.infusion.points.size(), 0, "a preview never writes the plan")
	assert_eq(preview.size(), 1)
	if preview.size() != 1:
		return
	assert_eq(preview[0].socket, 0)
	assert_eq(preview[0].infused, 80)


func test_a_fire_ride_row_yields_a_line_carrying_fires_status() -> void:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = ElementRoster.shared().by_id(&"fire").identity
	row.innate = 3
	spell.intakes = [row]
	var caster := _caster(0.0)
	var lines := ReadoutLines.for_infusion(spell, caster.stat_board, null)
	assert_eq(lines.size(), 1, "a Fire ride row is in play")
	if lines.size() != 1:
		return
	assert_eq(lines[0].aspect_id, &"fire")
	assert_eq(lines[0].status, _HEAT)


func test_a_socketed_line_reads_its_exchange_and_phrase() -> void:
	var caster := _caster(40.0)
	var plan := _plan(caster)
	plan.set_socket(0, &"poison")
	var line := ReadoutLines.lines(plan)[0]
	assert_eq(line.exchange(_VENOM), InfusionExchange.line(_VENOM, &"poison", 40))
	assert_eq(line.text(), "+ applies {poison:%s} stacks per hit (15 innate + 80 infused)"
			% NumFmt.num(line.per_hit))


func _of_kind(lines: Array[ReadoutLines.ReadoutLine], kind: ReadoutLines.Kind) -> Array[ReadoutLines.ReadoutLine]:
	var out: Array[ReadoutLines.ReadoutLine] = []
	for line in lines:
		if line.kind == kind:
			out.append(line)
	return out


func _terrain_of(element: StringName) -> StatusDef:
	return ElementRoster.shared().by_id(element).terrain


## A spell with one ride row of [param element], `plants` unset.
func _ride_row_spell(element: StringName, innate: int) -> SpellDef:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = ElementRoster.shared().by_id(element).identity
	row.innate = innate
	spell.intakes = [row]
	return spell


func test_a_forged_ride_yields_one_ride_line_reading_the_casts_load() -> void:
	var spell := SpellDef.new()
	var infusion := Infusion.for_cast(spell, {})
	infusion.set_ride(&"fire", 3)
	var board := _caster(0.0).stat_board
	var lines := ReadoutLines.for_infusion(spell, board, infusion)
	var rides := _of_kind(lines, ReadoutLines.Kind.RIDE)
	assert_eq(rides.size(), 1, "one ride line")
	if rides.size() != 1:
		return
	var ride := rides[0]
	assert_eq(ride.aspect_id, &"fire")
	assert_eq(ride.points, 3, "the ride's own points")
	assert_eq(ride.infused, Infusion.gained(spell, &"fire", 3))
	assert_eq(ride.total(), infusion.load_of(spell)[&"fire"], "the total is the cast's load")
	assert_eq(ride.status, _terrain_of(&"fire"), "a forged Fire ride plants Heat")
	assert_eq(ride.exchange(spell), InfusionExchange.line(spell, &"fire", 3))
	assert_string_contains(BadgeText.strip(ride.text()), _HEAT.identity.noun,
			"the line names the terrain it plants")
	assert_string_contains(ride.text(), "(%d forged)" % ride.infused, "the forged load, once")
	assert_null(AspectRoster.shared().by_id(&"fire"), "guard: an element is no aspect, so no badge")


func test_each_element_ride_row_names_its_terrain() -> void:
	var board := _caster(0.0).stat_board
	for element: StringName in [&"fire", &"ice", &"lightning"]:
		var lines := ReadoutLines.for_infusion(_ride_row_spell(element, 2), board, null)
		var rides := _of_kind(lines, ReadoutLines.Kind.RIDE)
		assert_eq(rides.size(), 1, "%s: one ride line, none dropped" % element)
		if rides.size() == 1:
			assert_eq(rides[0].status, _terrain_of(element), "%s: its terrain" % element)
			assert_string_contains(BadgeText.strip(rides[0].text()),
					_terrain_of(element).identity.noun, "%s: the line names its terrain" % element)
			assert_eq(rides[0].points, 0, "%s: innate only" % element)


func test_a_ride_replacing_the_authored_one_drops_the_cleared_line() -> void:
	var spell := _ride_row_spell(&"lightning", 2)
	var infusion := Infusion.for_cast(spell, {})
	infusion.set_ride(&"fire", 2)
	var lines := ReadoutLines.for_infusion(spell, _caster(0.0).stat_board, infusion)
	var rides := _of_kind(lines, ReadoutLines.Kind.RIDE)
	assert_eq(rides.size(), 1, "the forged ride alone")
	if rides.size() == 1:
		assert_eq(rides[0].aspect_id, &"fire")
	for line in lines:
		assert_ne(line.aspect_id, &"lightning", "no line for the cleared ride")


func test_a_shape_and_a_ride_of_different_elements_yield_one_line_each() -> void:
	var spell := SpellDef.new()
	var infusion := Infusion.for_cast(spell, {})
	infusion.set_shape(&"ice", 2)
	infusion.set_ride(&"fire", 1)
	var lines := ReadoutLines.for_infusion(spell, _caster(0.0).stat_board, infusion)
	var shapes := _of_kind(lines, ReadoutLines.Kind.SHAPE)
	var rides := _of_kind(lines, ReadoutLines.Kind.RIDE)
	assert_eq(shapes.size(), 1, "one shape line")
	assert_eq(rides.size(), 1, "one ride line")
	if shapes.size() == 1:
		assert_eq(shapes[0].aspect_id, &"ice")
		assert_eq(shapes[0].points, 2)
		assert_eq(shapes[0].exchange(spell), "", "a shape has no exchange yet")
	if rides.size() == 1:
		assert_eq(rides[0].aspect_id, &"fire")


func test_a_shape_alone_yields_a_shape_line_and_no_ride_line() -> void:
	var spell := SpellDef.new()
	var infusion := Infusion.for_cast(spell, {})
	infusion.set_shape(&"fire", 2)
	var lines := ReadoutLines.for_infusion(spell, _caster(0.0).stat_board, infusion)
	assert_eq(lines.size(), 1, "the shape line alone")
	assert_eq(_of_kind(lines, ReadoutLines.Kind.SHAPE).size(), 1)
	assert_eq(_of_kind(lines, ReadoutLines.Kind.RIDE).size(), 0)
	var plain := BadgeText.strip(lines[0].text())
	assert_string_contains(plain, ElementRoster.shared().by_id(&"fire").identity.noun)
	assert_false(plain.contains("{"), "the element token resolves")


func test_a_forged_ride_over_a_planting_row_of_its_element_carries_that_rows_status() -> void:
	var spell := _ride_row_spell(&"fire", 2)
	spell.intakes[0].plants = _HEAT
	var infusion := Infusion.for_cast(spell, {})
	infusion.set_ride(&"fire", 2)
	var rides := _of_kind(ReadoutLines.for_infusion(spell, _caster(0.0).stat_board, infusion),
			ReadoutLines.Kind.RIDE)
	assert_eq(rides.size(), 1, "one ride line: innate and forged on one element")
	if rides.size() != 1:
		return
	assert_eq(rides[0].status, _HEAT)
	assert_eq(rides[0].points, 2)
	assert_eq(rides[0].total(), infusion.load_of(spell)[&"fire"])


func test_previewing_a_socket_keeps_the_forged_ride() -> void:
	var plan := _plan(_caster(40.0))
	plan.set_ride(&"fire", 2)
	assert_eq(plan.infusion.ride_points, 2, "guard: the ride is forged")
	var preview := ReadoutLines.preview(plan, 0, &"poison")
	assert_eq(_of_kind(preview, ReadoutLines.Kind.RIDE).size(), 1, "the preview keeps the ride line")


func _shape_line(element: StringName, points: int) -> ReadoutLines.ReadoutLine:
	var spell := SpellDef.new()
	var infusion := Infusion.for_cast(spell, {})
	infusion.set_shape(element, points)
	var shapes := _of_kind(ReadoutLines.for_infusion(spell, _caster(0.0).stat_board, infusion),
			ReadoutLines.Kind.SHAPE)
	return shapes[0] if shapes.size() == 1 else null


func test_a_lightning_shape_line_reads_its_level_and_the_points_to_the_next() -> void:
	var line := _shape_line(&"lightning", 3)
	assert_not_null(line, "one shape line")
	if line == null:
		return
	var level := EdgeGoOff.level_for_points(3)
	assert_eq(line.shape_level, level, "the level is level_for_points'")
	var more := 1
	while EdgeGoOff.level_for_points(3 + more) == level:
		more += 1
	assert_eq(line.shape_next_points, more, "points to the next level")
	assert_eq(line.shape_radius, 0.0, "an arc has no radius")
	var plain := BadgeText.strip(line.text())
	assert_string_contains(plain, "level %d" % level)
	assert_string_contains(plain, "within %d hops" % level)
	var one := _shape_line(&"lightning", 1)
	if one != null:
		assert_string_contains(BadgeText.strip(one.text()), "within 1 hop (")


func test_a_fire_shape_line_reads_its_disc_radius_in_node_radii() -> void:
	var line := _shape_line(&"fire", 3)
	assert_not_null(line, "one shape line")
	if line == null:
		return
	var fire := ElementRoster.shared().by_id(&"fire")
	var disc: DiscGoOff = null
	for band in fire.bands:
		if band != null and band.go_off is DiscGoOff:
			disc = band.go_off
			break
	var radius := disc.shape_disc_radius(fire.shape_power(3), 0.0, 1.0)
	assert_almost_eq(line.shape_radius, radius, 0.0001, "the radius is shape_disc_radius'")
	assert_eq(line.shape_level, 0, "a disc has no level")
	assert_string_contains(BadgeText.strip(line.text()), NumFmt.num(snappedf(radius, 0.1)))


func test_an_ice_shape_line_carries_no_fire_or_lightning_reach() -> void:
	var line := _shape_line(&"ice", 2)
	assert_not_null(line, "one shape line")
	if line == null:
		return
	assert_eq(line.shape_level, 0)
	assert_eq(line.shape_radius, 0.0)
