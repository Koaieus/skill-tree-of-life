extends GutTest

## Addons attach as plain direct children of a SkillNode (#334) — no AddonAnchor
## bin, no ordering ritual. Covers the contract the deleted anchor used to
## enforce by convention: adoption of pre-existing children, idempotence across
## tree re-entry, symmetric detach, and the direct-children-only scope.

const SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")

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


func test_skill_node_scene_has_no_addon_anchor() -> void:
	assert_null(_node.get_node_or_null("Visuals/AddonAnchor"), "the AddonAnchor bin is gone (#334)")
