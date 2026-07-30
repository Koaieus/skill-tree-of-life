extends GutTest
## SkillNode.get_emblem_contributions() aggregation (docs/domain/skillnode-emblem.md):
## own archetype carve + keystone carve + SpellGrant carves + addons' get_emblem().
## SkillNode itself never interprets these — just collects specs for EmblemResolver.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const EmblemResolver = preload("res://skill_node/visuals/emblem/emblem_resolver.gd")

var _graph: Graph
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)


func test_default_node_with_no_archetype_contributes_nothing() -> void:
	var out := _node.get_emblem_contributions()
	assert_eq(out.size(), 0, "no archetype stamped -> the honest empty dome, no fallback shape")


func test_archetype_contributes_its_own_carve_shape() -> void:
	var str_arch: Archetype = load("res://archetypes/strength.tres")
	_node.archetype = str_arch
	var out := _node.get_emblem_contributions()
	assert_eq(out.size(), 1, "an archetype stamped -> its carve is the sole contribution")
	assert_eq(out[0].source_kind, &"archetype")
	assert_eq(out[0].polygon_sides, 3, "STR carves a triangle")


func test_keystone_contributes_a_keystone_carve() -> void:
	var ks := Keystone.new()
	ks.icon = null
	_node.keystone = ks
	var out := _node.get_emblem_contributions()
	var kinds := out.map(func(s): return s.source_kind)
	assert_true(kinds.has(&"keystone"), "keystone present → keystone carve contributed")
	for spec in out:
		if spec.source_kind == &"keystone":
			assert_eq(spec.priority, EmblemSpec.PRIORITY_KEYSTONE)


func test_spell_grant_effect_contributes_a_spell_carve() -> void:
	var grant := SpellGrant.new()
	grant.spell_def = SpellDef.new()
	_node.effects = [grant]
	var out := _node.get_emblem_contributions()
	var kinds := out.map(func(s): return s.source_kind)
	assert_true(kinds.has(&"spell"), "a SpellGrant effect → a spell carve")
	for spec in out:
		if spec.source_kind == &"spell":
			assert_eq(spec.priority, EmblemSpec.PRIORITY_SPELL)


func test_addon_get_emblem_is_aggregated() -> void:
	var anchor := _node.get_node_or_null("Visuals/AddonAnchor")
	assert_not_null(anchor, "fixture must have an AddonAnchor to attach the addon under")
	var dust := SkillDustAddon.new()
	anchor.add_child(dust)
	await get_tree().process_frame
	var out := _node.get_emblem_contributions()
	var kinds := out.map(func(s): return s.source_kind)
	assert_true(kinds.has(&"loot"), "SkillDustAddon.get_emblem() -> a loot carve, aggregated")
	dust.queue_free()


func test_resolver_picks_keystone_over_archetype_from_real_contributions() -> void:
	var ks := Keystone.new()
	_node.keystone = ks
	var out := _node.get_emblem_contributions()
	var res := EmblemResolver.resolve(out)
	assert_eq(res.carve.source_kind, &"keystone", "keystone outranks the archetype fallback end to end")
