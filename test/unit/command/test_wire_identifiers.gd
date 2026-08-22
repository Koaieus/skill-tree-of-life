extends GutTest

## The two identifiers #509 had to invent so a command could name something
## that is not a node or an entity: a temp-upgrade catalog entry, and a loot
## pick request.

const _MOD := preload("res://stats_system/stat_modifier.gd")


func test_every_catalog_entry_has_a_nonempty_id() -> void:
	for upgrade in MeleeAttackPlan.TEMP_UPGRADE_CATALOG:
		assert_true(upgrade.has("id"), "catalog entry carries an id")
		assert_ne(upgrade.id, &"", "and it is not empty")


func test_catalog_ids_are_unique() -> void:
	var seen: Array[StringName] = []
	for upgrade in MeleeAttackPlan.TEMP_UPGRADE_CATALOG:
		assert_false(seen.has(upgrade.id), "id %s is unique" % upgrade.id)
		seen.append(upgrade.id)


## Load-bearing: `can_apply_temp_upgrade` gates on
## `TEMP_UPGRADE_CATALOG.has(upgrade)`, so a lookup that rebuilt the dictionary
## would resolve to something the plan then rejects.
func test_upgrade_by_id_returns_the_catalog_entry_itself() -> void:
	for upgrade in MeleeAttackPlan.TEMP_UPGRADE_CATALOG:
		var found := MeleeAttackPlan.upgrade_by_id(upgrade.id)
		assert_true(MeleeAttackPlan.TEMP_UPGRADE_CATALOG.has(found),
				"round-tripped entry is still a catalog member")
		assert_eq(found.scene, upgrade.scene)
		assert_eq(found.script, upgrade.script)


func test_upgrade_by_id_on_an_unknown_id_is_empty() -> void:
	assert_true(MeleeAttackPlan.upgrade_by_id(&"no_such_upgrade").is_empty())


## A ToggleTempUpgradeCommand's payload resolves back to a real catalog entry —
## the whole point of the owner's correction to #509's payload table.
func test_a_toggle_command_names_a_resolvable_upgrade() -> void:
	var upgrade: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0]
	var cmd := ToggleTempUpgradeCommand.new(1, 2, upgrade.id)
	var back := CommandCodec.from_dict(cmd.to_dict()) as ToggleTempUpgradeCommand

	assert_not_null(back)
	assert_eq(MeleeAttackPlan.upgrade_by_id(back.upgrade_id), upgrade)


func _request() -> LootPickRequest:
	var candidates: Array[StatModifier] = [_MOD.new(), _MOD.new()]
	return LootPickRequest.new(null, candidates, func(_chosen: Array) -> void: pass)


func test_loot_pick_requests_get_distinct_nonzero_ids() -> void:
	var a := _request()
	var b := _request()

	assert_ne(a.request_id, 0)
	assert_ne(a.request_id, b.request_id)


func test_a_pick_command_can_answer_a_specific_request() -> void:
	var req := _request()
	var cmd := PickLootCommand.new(0, req.request_id, 1)
	var back := CommandCodec.from_dict(cmd.to_dict()) as PickLootCommand

	assert_not_null(back)
	assert_eq(back.request_id, req.request_id)
	assert_eq(back.chosen_index, 1)
