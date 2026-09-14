extends GutTest

## #893 — a StatModifier's resource_name must keep its formula's "per" phrase
## across a save/load round trip. Before the fix, the `stat_id` / `operation`
## / `value` setters (in export order) each fire `_update_resource_name()`
## during deserialization, and `formula` — the last field, with no setter —
## hasn't landed yet, so the final recompute renders a formula-less name and
## clobbers the complete one stored in the `.tres`.

const _TEMP_PATH := "user://test_stat_modifier_name_on_load.tres"


func after_each() -> void:
	if FileAccess.file_exists(_TEMP_PATH):
		DirAccess.remove_absolute(_TEMP_PATH)


func _mod_with_formula() -> StatModifier:
	var formula := RatioFormula.new()
	formula.source_stat_id = &"intelligence"
	formula.divisor = 10.0
	var m := StatModifier.new()
	m.stat_id = &"xp_per_turn"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 1.0
	m.formula = formula
	return m


func test_resource_name_keeps_per_phrase_after_save_and_load() -> void:
	var m := _mod_with_formula()
	# `_mod_with_formula` assigns fields in export/declaration order (stat_id,
	# operation, value, formula) — the same order `.tres` deserialization
	# uses. This first assertion exercises the root cause directly: without a
	# `formula` setter, the last recompute happens before `formula` lands and
	# the per-phrase never makes it into `resource_name` even on construction.
	assert_true(" per " in m.resource_name,
		"resource_name should already carry the per-phrase after construction (got '%s')" % m.resource_name)

	assert_eq(ResourceSaver.save(m, _TEMP_PATH), OK, "temp .tres saved")
	var loaded: StatModifier = ResourceLoader.load(_TEMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(loaded, "temp .tres loaded")
	assert_true(" per " in loaded.resource_name,
		"loaded resource_name should keep the per-phrase, got '%s'" % loaded.resource_name)
	assert_eq(loaded.resource_name, m.resource_name,
		"round-tripped name should match the original exactly")
