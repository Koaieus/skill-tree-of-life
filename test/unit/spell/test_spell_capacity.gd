extends GutTest

## [method SpellDef.capacity_at]: overqualified casting's one formula — the
## base cap at [member SpellDef.min_degree], plus
## [member SpellDef.infusion_capacity_per_degree] per degree above it. Asserted
## against the def's own fields, never the shipped defaults.


func _spell(base: float, per_degree: int, min_degree: int) -> SpellDef:
	var spell := SpellDef.new()
	spell.infusion_capacity = base
	spell.infusion_capacity_per_degree = per_degree
	spell.min_degree = min_degree
	return spell


func test_capacity_is_the_base_at_min_degree_and_grows_per_degree_above_it() -> void:
	var spell := _spell(7.0, 3, 2)
	var base := floori(spell.infusion_capacity)
	assert_eq(spell.capacity_at(spell.min_degree), base, "the base cap at min_degree")
	for n in [1, 2, 5]:
		assert_eq(spell.capacity_at(spell.min_degree + n),
				base + spell.infusion_capacity_per_degree * n,
				"B + K × n at min_degree + %d" % n)


func test_a_fractional_base_floors() -> void:
	var spell := _spell(4.9, 2, 1)
	assert_eq(spell.capacity_at(spell.min_degree), 4)
	assert_eq(spell.capacity_at(spell.min_degree + 1), 4 + spell.infusion_capacity_per_degree)


func test_no_per_degree_bonus_leaves_every_degree_at_the_base() -> void:
	var spell := _spell(6.0, 0, 1)
	for d in [1, 2, 9]:
		assert_eq(spell.capacity_at(d), floori(spell.infusion_capacity))


func test_an_inf_base_enforces_no_total_at_any_degree() -> void:
	var spell := _spell(INF, 3, 2)
	for d in [0, 2, 3, 40]:
		assert_eq(spell.capacity_at(d), SpellDef.UNCAPPED,
				"an INF base is uncapped at degree %d" % d)
