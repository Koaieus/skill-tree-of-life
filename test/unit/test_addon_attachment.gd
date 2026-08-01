extends GutTest

## Addons attach as plain direct children of a SkillNode (#334) — no AddonAnchor
## bin, no ordering ritual. Covers the contract the deleted anchor used to
## enforce by convention: adoption of pre-existing children, idempotence across
## tree re-entry, symmetric detach, and the direct-children-only scope.

const SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")
const FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")
const BOARD := preload("res://entity/default_entity_board.tres")

var _node: SkillNode


func before_each() -> void:
	_node = SKILL_NODE_SCENE.instantiate()


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _armor() -> float:
	return float(_node.get_local_value(&"armor"))


func test_addon_added_after_ready_attaches() -> void:
	add_child(_node)
	await get_tree().process_frame
	_node.add_child(BUNKER_SCENE.instantiate())
	assert_eq(_node.get_addons().size(), 1, "a direct child addon is reported")
	assert_almost_eq(_armor(), 5.0, 0.001, "bunker's local armor modifier landed on node_board")


func test_addon_parented_before_the_carrier_enters_the_tree_is_adopted() -> void:
	# The exact case the old anchor made silently inert — the whole point of #334.
	_node.add_child(BUNKER_SCENE.instantiate())
	assert_eq(_node.get_addons().size(), 0, "nothing attaches before _ready")
	add_child(_node)
	await get_tree().process_frame
	assert_eq(_node.get_addons().size(), 1, "_ready adopts the pre-existing addon child")
	assert_almost_eq(_armor(), 5.0, 0.001, "adoption transfers modifiers, not just visuals")


func test_adoption_orders_correctly_against_hp_binding() -> void:
	# Adoption runs EARLIER in _ready than any addon ever attached before, so a
	# node_health-carrying addon now mints the combat PoolStat before
	# _refresh_hp_binding seeds it. Pin that the seeding still wins and the
	# addon's bonus is included, rather than one clobbering the other.
	var entity := Entity.new()
	entity.stat_board = BOARD.duplicate(true) as StatBoard
	add_child_autofree(entity)
	_node.add_child(FORTIFICATION_SCENE.instantiate())
	_node.owned_by = entity
	add_child(_node)
	await get_tree().process_frame

	var baseline := float(entity.stat_board.get_stat(&"node_health").get_value())
	assert_almost_eq(_node.get_max_hp(), baseline + 15.0, 0.001,
			"fortification's +15 node_health rides on top of the entity baseline")
	assert_almost_eq(_node.get_current_hp(), _node.get_max_hp(), 0.001,
			"the refill in _refresh_hp_binding saw the adopted addon's bonus")


func test_removing_the_addon_reverts_the_modifier() -> void:
	add_child(_node)
	await get_tree().process_frame
	var addon := BUNKER_SCENE.instantiate() as SkillNodeAddon
	_node.add_child(addon)
	assert_almost_eq(_armor(), 5.0, 0.001, "attached")
	_node.remove_child(addon)
	addon.free()
	assert_eq(_node.get_addons().size(), 0, "ledger drops it")
	assert_almost_eq(_armor(), 0.0, 0.001, "detach reclaims the local modifier")


func test_carrier_tree_re_entry_does_not_double_apply() -> void:
	# child_entered_tree re-fires for EVERY existing child when the carrier
	# re-enters the tree — verified empirically. Only the _addons ledger keeps
	# this from stacking the modifier a second time.
	add_child(_node)
	await get_tree().process_frame
	_node.add_child(BUNKER_SCENE.instantiate())
	assert_almost_eq(_armor(), 5.0, 0.001, "attached once")

	remove_child(_node)
	add_child(_node)
	await get_tree().process_frame

	assert_eq(_node.get_addons().size(), 1, "still exactly one addon after re-entry")
	assert_almost_eq(_armor(), 5.0, 0.001, "armor did NOT stack to 10")


func test_only_direct_children_are_adopted() -> void:
	# Documented non-contract: nesting resolves `carrier` but never attaches.
	add_child(_node)
	await get_tree().process_frame
	var addon := BUNKER_SCENE.instantiate() as SkillNodeAddon
	_node.get_node("Visuals").add_child(addon)
	await get_tree().process_frame
	assert_eq(_node.get_addons().size(), 0, "a nested addon is not adopted")
	assert_almost_eq(_armor(), 0.0, 0.001, "and grants nothing")


func test_unique_addon_duplicate_is_rejected() -> void:
	add_child(_node)
	await get_tree().process_frame
	var first := BUNKER_SCENE.instantiate() as SkillNodeAddon
	first.unique = true
	_node.add_child(first)
	var second := BUNKER_SCENE.instantiate() as SkillNodeAddon
	second.unique = true
	_node.add_child(second)
	assert_eq(_node.get_addons().size(), 1, "the duplicate unique addon was rejected")
	assert_push_error("Duplicate unique addon res://skill_node/addons/skill_node_addon.gd on SkillNode; rejecting.")


func test_get_addons_returns_a_copy() -> void:
	# Accessor contract from .claude/rules/graph.md — callers may mutate it.
	add_child(_node)
	await get_tree().process_frame
	_node.add_child(BUNKER_SCENE.instantiate())
	var addons := _node.get_addons()
	addons.clear()
	assert_eq(_node.get_addons().size(), 1, "mutating the returned array left the ledger intact")


func test_every_concrete_addon_scene_gets_the_base_z() -> void:
	# BASE_Z lives on SkillNodeAddon._ready, not on the carrier. Authoring it
	# into skill_node_addon.tscn would NOT cover these — they are standalone
	# scenes carrying the base script, not inherited from that template.
	var scenes: Array[String] = [
		"res://skill_node/addons/bunker_addon.tscn",
		"res://skill_node/addons/fortification_addon.tscn",
		"res://skill_node/addons/clamp_addon.tscn",
		"res://skill_node/addons/spike_ring_addon.tscn",
		"res://skill_node/addons/skill_dust_addon.tscn",
	]
	add_child(_node)
	await get_tree().process_frame
	for path in scenes:
		var addon: SkillNodeAddon = load(path).instantiate()
		_node.add_child(addon)
		await get_tree().process_frame
		assert_eq(addon.z_index, SkillNodeAddon.BASE_Z, "%s draws above the Visuals subtree" % path)
		_node.remove_child(addon)
		addon.free()


func test_skill_node_scene_has_no_addon_anchor() -> void:
	assert_null(_node.get_node_or_null("Visuals/AddonAnchor"), "the AddonAnchor bin is gone (#334)")
