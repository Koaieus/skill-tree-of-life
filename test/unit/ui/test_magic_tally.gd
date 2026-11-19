extends GutTest

## [method MagicBody.tally_text]: the aspects' points over the spell's cap —
## [method Infusion.total_points] / [member SpellDef.infusion_capacity]; the
## shape and the ride never count, an uncapped spell shows the used count alone.

const _CAP := 10


func _spell(cap: float) -> SpellDef:
	var spell := SpellDef.new()
	spell.infusion_capacity = cap
	return spell


func test_the_tally_reads_the_aspect_points_over_the_cap() -> void:
	var spell := _spell(_CAP)
	var infusion := Infusion.for_cast(spell, {&"poison": 3})
	infusion.set_ride(&"fire", 2)
	infusion.set_shape(&"ice", 1)
	assert_eq(infusion.total_points(), 3, "guard: the aspects alone")
	assert_eq(MagicBody.tally_text(spell, infusion), "%d / %d" % [infusion.total_points(), _CAP])


func test_a_ride_point_leaves_the_used_count_and_an_aspect_point_moves_it() -> void:
	var spell := _spell(_CAP)
	var infusion := Infusion.for_cast(spell, {&"poison": 3})
	var before := MagicBody.tally_text(spell, infusion)
	infusion.set_ride(&"fire", 1)
	assert_eq(MagicBody.tally_text(spell, infusion), before, "a ride point is not counted")
	var more := infusion.rebuilt(spell, {&"poison": 4})
	assert_eq(MagicBody.tally_text(spell, more), "4 / %d" % _CAP, "one aspect point moves it by one")


func test_an_uncapped_spell_shows_the_used_count_alone() -> void:
	var spell := _spell(INF)
	var infusion := Infusion.for_cast(spell, {&"poison": 3})
	assert_eq(MagicBody.tally_text(spell, infusion), "3")


func test_no_spell_shows_no_tally() -> void:
	assert_eq(MagicBody.tally_text(null, null), "")
