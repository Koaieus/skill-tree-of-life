extends GutTest

## [method InfusionExchange.line]: `spent → +gained <rate>`, gained floored at
## the spell's ingest rate, the floor's dropped points named as wasted. The
## expected numbers come from the rate, never from a shipped `.tres`.


func _spell(rate: float) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Test Bolt"
	spell.default_rate = rate
	return spell


func test_rate_two_doubles_with_a_times_suffix() -> void:
	var rate := 2.0
	assert_eq(InfusionExchange.line(_spell(rate), &"poison", 40),
			"40 → +%d ×2" % floori(40 * rate))


func test_rate_half_shows_a_half() -> void:
	var rate := 0.5
	assert_eq(InfusionExchange.line(_spell(rate), &"poison", 40),
			"40 → +%d ½" % floori(40 * rate))


func test_rate_one_has_no_suffix() -> void:
	assert_eq(InfusionExchange.line(_spell(1.0), &"poison", 40), "40 → +40")


func test_the_floor_names_the_wasted_points() -> void:
	var rate := 0.5
	var gained := floori(41 * rate)
	var wasted := 41 - ceili(gained / rate)
	assert_eq(wasted, 1, "guard: 41 at ½ drops one")
	assert_eq(InfusionExchange.line(_spell(rate), &"poison", 41),
			"41 → +%d ½ · %d wasted" % [gained, wasted])


func test_rate_zero_is_refused() -> void:
	assert_eq(InfusionExchange.line(_spell(0.0), &"poison", 40), "refused")
