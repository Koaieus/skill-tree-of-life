extends GutTest

## The two identifiers #509 had to invent so a command could name something
## that is not a node or an entity: a temp-upgrade catalog entry, and a loot
## pick request.

const _MOD := preload("res://stats_system/stat_modifier.gd")
## A `var`, not a `const`: the parser constant-folds `CONST.kinds[i]`.
var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")


func test_every_catalog_entry_has_a_nonempty_id() -> void:
	for upgrade in _catalog.kinds:
		assert_ne(upgrade.id, &"", "catalog entry carries a non-empty id")


func test_catalog_ids_are_unique() -> void:
	var seen: Array[StringName] = []
	for upgrade in _catalog.kinds:
		assert_false(seen.has(upgrade.id), "id %s is unique" % upgrade.id)
		seen.append(upgrade.id)


## Load-bearing: consumers compare defs by reference (`kinds.has(def)`,
## `addon.temp_upgrade_def == def`), so a lookup that rebuilt the def would
## resolve to something the plan then rejects.
func test_by_id_returns_the_catalog_entry_itself() -> void:
	for upgrade in _catalog.kinds:
		var found := _catalog.by_id(upgrade.id)
		assert_true(found == upgrade, "round-tripped def is the catalog member itself")


func test_by_id_on_an_unknown_id_is_null() -> void:
	assert_null(_catalog.by_id(&"no_such_upgrade"))


## A ToggleTempUpgradeCommand's payload resolves back to a real catalog entry —
## the whole point of the owner's correction to #509's payload table — through
## the same door the handler uses, [method BattleSystem.temp_upgrade_by_id].
func test_a_toggle_command_names_a_resolvable_upgrade() -> void:
	var upgrade: TempUpgradeDef = _catalog.kinds[0]
	var bs: BattleSystem = autofree(BattleSystem.new())
	bs.temp_upgrade_catalog = _catalog
	var cmd := ToggleTempUpgradeCommand.new(1, 2, upgrade.id)
	var back := CommandCodec.from_dict(cmd.to_dict()) as ToggleTempUpgradeCommand

	assert_not_null(back)
	assert_true(bs.temp_upgrade_by_id(back.upgrade_id) == upgrade, "identical def")


func _request() -> LootPickRequest:
	var candidates: Array[StatModifier] = [_MOD.new(), _MOD.new()]
	return LootPickRequest.new(null, candidates, func(_chosen: Array) -> void: pass)


func _registry() -> LootPickRegistry:
	var registry := LootPickRegistry.new()
	autofree(registry)
	return registry


## A request mints NOTHING on its own (#522). The id used to come from a
## per-process `static var` on [LootPickRequest], which is exactly what a wire
## id must not be — two processes hand the same id to different requests the
## moment their request COUNTS diverge.
func test_an_unregistered_request_has_no_id() -> void:
	assert_eq(_request().request_id, 0, "0 keeps meaning 'no request'")


func test_the_registry_mints_distinct_nonzero_ids() -> void:
	var registry := _registry()
	var a := _request()
	var b := _request()

	registry.park(a)
	registry.park(b)

	assert_ne(a.request_id, 0)
	assert_ne(a.request_id, b.request_id)


## The reason [SpellLootRequest] needed no second counter and
## [PickLootCommand] needs no kind discriminator: ONE authority, ONE id space,
## both request kinds addressed by the same field.
func test_both_request_kinds_share_one_id_space() -> void:
	var registry := _registry()
	var stat_request := _request()
	var spell_request := SpellLootRequest.new(
			null, [] as Array[SpellDef], func(_chosen: Array) -> void: pass)

	registry.park(stat_request)
	registry.park(spell_request)

	assert_ne(spell_request.request_id, 0, "a spell draft is addressable now")
	assert_ne(stat_request.request_id, spell_request.request_id)


func test_a_pick_command_can_answer_a_specific_request() -> void:
	var req := _request()
	_registry().park(req)
	var cmd := PickLootCommand.new(0, req.request_id, 1)
	var back := CommandCodec.from_dict(cmd.to_dict()) as PickLootCommand

	assert_not_null(back)
	assert_eq(back.request_id, req.request_id)
	assert_eq(back.chosen_index, 1)
