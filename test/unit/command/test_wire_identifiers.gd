extends GutTest

## The identifiers a command uses to name something that is not a node or an
## entity: a temp-upgrade kind (its addon scene path), and a loot pick request.

const _MOD := preload("res://stats_system/stat_modifier.gd")
var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")


## A temp upgrade's wire identity is its kind — the addon's scene path.
func test_every_catalog_kind_is_a_nonempty_scene_path() -> void:
	for scene in _catalog.kinds():
		assert_ne(scene.resource_path, "", "catalog kind carries a scene path")


func test_catalog_kinds_are_unique() -> void:
	var seen: Array[String] = []
	for scene in _catalog.kinds():
		assert_false(seen.has(scene.resource_path), "kind %s is unique" % scene.resource_path)
		seen.append(scene.resource_path)


## Load-bearing: the lookup must hand back the very scene the catalog holds —
## the same object a `preload` of that path is — never a rebuilt copy.
func test_by_kind_returns_the_catalog_entry_itself() -> void:
	for scene in _catalog.kinds():
		var found := _catalog.by_kind(scene.resource_path)
		assert_true(found == scene, "round-tripped kind is the catalog member itself")


func test_by_kind_on_an_unknown_kind_is_null() -> void:
	assert_null(_catalog.by_kind("res://no_such_upgrade_addon.tscn"))


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
