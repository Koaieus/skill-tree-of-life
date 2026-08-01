extends GutTest
## SkillNode.get_emblem_contributions() aggregation (docs/domain/skillnode-emblem.md):
## own archetype carve + keystone carve + SpellGrant carves + addons' get_emblem().
## SkillNode itself never interprets these — just collects specs for EmblemResolver.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const EmblemResolver = preload("res://skill_node/visuals/emblem/emblem_resolver.gd")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")

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
	assert_eq(out[0].shape.sides, 3, "STR carves a triangle")


func test_keystone_contributes_a_keystone_carve() -> void:
	var ks := Keystone.new()
	ks.carve_shape = null
	_node.keystone = ks
	var out := _node.get_emblem_contributions()
	var kinds := out.map(func(s): return s.source_kind)
	assert_true(kinds.has(&"keystone"), "keystone present → keystone carve contributed")
	for spec in out:
		if spec.source_kind == &"keystone":
			assert_eq(spec.priority, EmblemSpec.Priority.KEYSTONE)


func test_spell_grant_effect_contributes_a_spell_carve() -> void:
	var grant := SpellGrant.new()
	grant.spell_def = SpellDef.new()
	_node.effects = [grant]
	var out := _node.get_emblem_contributions()
	var kinds := out.map(func(s): return s.source_kind)
	assert_true(kinds.has(&"spell"), "a SpellGrant effect → a spell carve")
	for spec in out:
		if spec.source_kind == &"spell":
			assert_eq(spec.priority, EmblemSpec.Priority.SPELL)


func test_addon_get_emblem_is_aggregated() -> void:
	var dust := SkillDustAddon.new()
	_node.add_child(dust)
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


# ── The shape flows source -> spec -> resolution (#315, D3) ─────────────────

## A keystone's own carve_shape reaches the resolved spec — no icon-to-payload
## hop in between. Typed as the BASE CarveShape on purpose, so a keystone is not
## restricted to a baked texture carve.
func test_keystone_carve_shape_flows_into_the_resolved_spec() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 8
	var ks := Keystone.new()
	ks.carve_shape = shape
	_node.keystone = ks
	_node.archetype = load("res://archetypes/strength.tres")

	var res := EmblemResolver.resolve(_node.get_emblem_contributions())
	assert_eq(res.carve.source_kind, &"keystone", "keystone outranks the archetype fallback")
	assert_same(res.carve.shape, shape, "and it carves ITS shape, not the archetype triangle")


## Acceptance #4's decisive case: a PolygonCarveShape on a SpellDef. If the
## field were typed TextureCarveShape this would not even assign — the base-class
## typing is load-bearing, not decorative.
func test_spell_def_takes_any_carve_shape_not_just_a_texture_one() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 6
	shape.squish_x = 0.6
	var grant := SpellGrant.new()
	grant.spell_def = SpellDef.new()
	grant.spell_def.carve_shape = shape
	_node.effects = [grant]
	_node.archetype = load("res://archetypes/strength.tres")

	var res := EmblemResolver.resolve(_node.get_emblem_contributions())
	assert_eq(res.carve.source_kind, &"spell", "a spell grant outranks the archetype fallback")
	assert_true(res.carve.shape is PolygonCarveShape, "a spell may carve a polygon, not only baked art")
	assert_eq(res.carve.shape.sides, 6)
	assert_eq(res.carve.shape.squish_x, 0.6)


## Null carve_shape is NOT "contribute nothing": the source still claims its rung
## so the node reads as an empty dome, rather than the archetype fallback winning
## and dressing a keystone node up as a plain territory node.
func test_shapeless_keystone_still_claims_the_carve() -> void:
	var ks := Keystone.new()
	ks.carve_shape = null
	_node.keystone = ks
	_node.archetype = load("res://archetypes/strength.tres")

	var res := EmblemResolver.resolve(_node.get_emblem_contributions())
	assert_eq(res.carve.source_kind, &"keystone")
	assert_null(res.carve.shape, "no shape authored -> empty dome, not the archetype triangle")
