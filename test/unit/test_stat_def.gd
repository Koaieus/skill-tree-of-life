extends GutTest

## #729 — `StatDef.lower_is_better` + `is_improvement(delta)`. The accessor is
## a DELTA predicate only (decision 4): it can't judge an absolute value, only
## whether a change is better or worse. Zero is never an improvement.


func test_default_def_more_is_better() -> void:
	var def := StatDef.new()
	assert_true(def.is_improvement(1.0))
	assert_false(def.is_improvement(-1.0))
	assert_false(def.is_improvement(0.0))


func test_lower_is_better_flips_the_sign_and_leaves_zero_false() -> void:
	var def := StatDef.new()
	def.lower_is_better = true
	assert_true(def.is_improvement(-1.0))
	assert_false(def.is_improvement(1.0))
	assert_false(def.is_improvement(0.0))


func test_min_damage_taken_and_dealloc_damage_are_lower_is_better() -> void:
	assert_true(StatRegistry.get_def(&"min_damage_taken").lower_is_better,
			"min_damage_taken should flip polarity — a lower floor is good")
	assert_true(StatRegistry.get_def(&"dealloc_damage").lower_is_better,
			"dealloc_damage should flip polarity — less chip damage is good")


func test_armor_stays_default_more_is_better() -> void:
	assert_false(StatRegistry.get_def(&"armor").lower_is_better)
