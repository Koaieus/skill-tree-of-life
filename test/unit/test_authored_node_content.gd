extends GutTest

## Guards the *hand-authored* content resources against silent decay. The
## generic substrate tests (test_keystone.gd, test_effect.gd) build their own
## fixtures, so a `.tres` that got stripped by an editor round-trip (see
## .claude/rules/godot-workflow.md) still passes them. These load the real
## files and assert the modifiers a designer typed in are still there — and
## still land on the board they're aimed at.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _XP_ANCHOR := preload("res://entity/keystone/instances/xp_anchor_keystone.tres")
const _BUNKER := preload("res://skill_node/addons/bunker_addon.tscn")
const _FORTIFICATION := preload("res://skill_node/addons/fortification_addon.tscn")


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return ent


func _make_node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	autofree(n)
	return n


# ── Keystone: XP Anchor ──────────────────────────────────────────────────────

func test_xp_anchor_keystone_still_carries_its_modifier() -> void:
	var ks = _XP_ANCHOR
	assert_true(ks is Keystone, "xp_anchor_keystone.tres must keep its script")
	assert_eq(ks.display_name, "XP Anchor")
	assert_eq(ks.effects.size(), 1, "authored effect payload was stripped")
	var fx: Effect = ks.effects[0]
	assert_true(fx is StatEffect, "payload entry lost its script")
	assert_eq(fx.modifiers.size(), 1, "authored modifier bundle was stripped")
	var m: StatModifier = fx.modifiers[0]
	assert_not_null(m, "modifier entry lost its script")
	assert_eq(m.stat_id, &"xp_per_turn")
	assert_eq(m.value, 4.0)


func test_xp_anchor_lands_on_an_allocating_entity() -> void:
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	node.keystone = _XP_ANCHOR
	var base: float = ent.stat_board.get_stat(&"xp_per_turn").value

	alloc.force_allocate(ent, node)
	assert_eq(ent.stat_board.get_stat(&"xp_per_turn").value, base + 4.0,
		"allocating the XP Anchor node must grant +4 xp_per_turn")

	alloc.force_deallocate(node)
	assert_eq(ent.stat_board.get_stat(&"xp_per_turn").value, base,
		"deallocating must revoke it exactly")


# ── Addons: local (node_board) modifiers ─────────────────────────────────────

## `local_modifiers` are node-scoped: they hit `carrier.node_board`, never the
## entity board, and they apply whether or not the carrier is allocated.
func _assert_local_modifier(scene: PackedScene, stat_id: StringName, delta: float) -> void:
	var node := _make_node()
	add_child(node)
	await get_tree().process_frame

	var addon: SkillNodeAddon = scene.instantiate()
	assert_eq(addon.local_modifiers.size(), 1,
		"%s: authored local_modifiers were stripped" % scene.resource_path)
	assert_eq(addon.local_modifiers[0].stat_id, stat_id)
	assert_eq(addon.local_modifiers[0].value, delta)

	var before: float = float(node.get_local_value(stat_id))
	node.add_child(addon)
	await get_tree().process_frame
	assert_eq(float(node.get_local_value(stat_id)), before + delta,
		"%s: local modifier never reached node_board" % scene.resource_path)

	addon.get_parent().remove_child(addon)
	addon.free()
	assert_eq(float(node.get_local_value(stat_id)), before,
		"%s: removing the addon must unwind its local modifier" % scene.resource_path)


func test_bunker_addon_grants_node_local_armor() -> void:
	await _assert_local_modifier(_BUNKER, &"armor", 5.0)


func test_fortification_addon_grants_node_local_health() -> void:
	await _assert_local_modifier(_FORTIFICATION, &"node_health", 15.0)


## A scene-authored owned node (`owned_by` baked into the .tscn, the
## dev_sandbox shape) must reach the same board state a `force_allocate`d one
## does. `register_scene_authored_ownership` is a THIRD setup path next to
## `allocate` / `force_allocate` and it re-lists their side effects by hand —
## it was missing `apply_entity_modifiers_to` outright, so dev_sandbox's
## hand-authored owned nodes granted the player nothing at all. (The structural
## fix is one teardown/setup atom — triage C11.)
func test_scene_authored_ownership_applies_node_modifiers() -> void:
	var graph: Graph = preload("res://graph/graph.tscn").instantiate()
	add_child_autofree(graph)
	var ent := _make_entity()
	graph.add_child(ent)

	var node: SkillNode = _NODE_SCENE.instantiate()
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 7.0
	node.modifiers = [m]
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame

	var before: float = ent.stat_board.get_stat(&"strength").value
	node.owned_by = ent  # what the .tscn bakes
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	autofree(alloc)
	alloc.graph = graph
	alloc.register_scene_authored_ownership()

	assert_eq(ent.stat_board.get_stat(&"strength").value, before + 7.0,
		"a hand-authored owned node's modifiers must reach its owner's board")
	assert_eq(node.allocation_level, 1, "and the first allocation slot is filled")


## Every StatModifier authored as a sub-resource of an addon scene must be
## `resource_local_to_scene`, or all instances of that addon share ONE modifier
## object. That is not a theoretical leak: the #376 local-scale mutator writes
## `m.value` in place — deliberately, since the boards hold references — so a
## shared instance means scaling one node's Spikes rescales every Spikes on the
## board (spike_ring_addon.tscn's `Resource_u38nb` shipped exactly that way).
##
## Asserted by identity across two instantiations rather than by reading the
## flag, because sharing is the actual defect and `instantiate()` is the only
## thing that honours the flag.
func test_addon_scenes_never_share_a_modifier_instance_between_carriers() -> void:
	for path in _addon_scene_paths():
		var scene: PackedScene = load(path)
		var a: SkillNodeAddon = autofree(scene.instantiate())
		var b: SkillNodeAddon = autofree(scene.instantiate())
		var a_mods: Array[StatModifier] = _authored_modifiers(a)
		var b_mods: Array[StatModifier] = _authored_modifiers(b)
		assert_eq(a_mods.size(), b_mods.size(), "%s: two instances disagree on payload size" % path)
		for i in a_mods.size():
			assert_true(
				a_mods[i] != b_mods[i],
				"%s: modifier %d ('%s') is SHARED between instances — add resource_local_to_scene = true"
					% [path, i, a_mods[i].stat_id]
			)


func _authored_modifiers(a: SkillNodeAddon) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for m in a.local_modifiers + a.entity_modifiers:
		if m != null:
			out.append(m)
	return out


func _addon_scene_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("res://skill_node/addons/"):
		if f.ends_with(".tscn"):
			out.append("res://skill_node/addons/".path_join(f))
	assert_gt(out.size(), 0, "found no addon scenes to walk — did the directory move?")
	return out
