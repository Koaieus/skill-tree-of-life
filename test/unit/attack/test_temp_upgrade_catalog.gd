extends GutTest

## The authored temp-upgrade catalog (#1008): a `.tres` of [TempUpgradeDef]s
## reached through [member BattleSystem.temp_upgrade_catalog]. Preloading it
## from a TEST script is not the parse cycle the catalog script itself must
## avoid.

const CATALOG: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")


func test_the_catalog_is_not_empty() -> void:
	assert_gt(CATALOG.kinds.size(), 0, "authored kinds")


func test_every_kind_is_fully_authored() -> void:
	var seen: Array[StringName] = []
	for def in CATALOG.kinds:
		assert_not_null(def)
		assert_ne(def.id, &"", "a kind carries a wire id")
		assert_false(seen.has(def.id), "id %s is unique" % def.id)
		seen.append(def.id)
		assert_not_null(def.scene, "%s has a scene" % def.id)
		assert_not_null(def.addon_script, "%s has an addon_script" % def.id)
		assert_gt(def.cost, 0, "%s costs something" % def.id)


## Load-bearing: consumers compare defs by reference, so `by_id` must hand
## back the object `kinds` holds, never a copy.
func test_by_id_returns_the_kinds_entry_itself() -> void:
	var clamp := CATALOG.by_id(&"clamp")
	assert_not_null(clamp)
	assert_true(CATALOG.kinds.has(clamp), "the same object kinds holds")
	var kinds: Array[TempUpgradeDef] = CATALOG.kinds
	assert_true(clamp == kinds.front(), "clamp is the first tray slot")
	for def in CATALOG.kinds:
		assert_true(CATALOG.by_id(def.id) == def, "%s round-trips by identity" % def.id)


func test_by_id_on_an_unknown_id_is_null() -> void:
	assert_null(CATALOG.by_id(&"no_such_upgrade"))
	assert_null(CATALOG.by_id(&""))
