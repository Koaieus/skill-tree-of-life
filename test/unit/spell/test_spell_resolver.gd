extends GutTest

## SpellResolver: the BFS driver. Should null-guard, emit hits in
## hop-monotonic order (VFX layer staggers off this), and run every
## on-hit effect in declaration order at every state.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


class _RecordingEffect extends OnHitEffect:
	var calls: Array[StringName] = []
	var label: StringName = &""
	func apply(_state: CastSpell, _outcome: AttackOutcome) -> void:
		calls.append(label)


func test_null_spell_returns_empty_outcome() -> void:
	var out := SpellResolver.resolve(null, null, null, null, null)
	assert_not_null(out)
	assert_eq(out.hits.size(), 0)


func test_null_propagation_returns_empty_outcome() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var spell := SpellDef.new()
	spell.propagation = null
	var out := SpellResolver.resolve(spell, n[0], n[0], null, graph)
	assert_eq(out.hits.size(), 0)


func test_hop_index_is_monotonic() -> void:
	# Line 0(atk) - 1 - 2 - 3. With max_hops=3 the resolver visits in BFS
	# order so hop_index on resulting hits is non-decreasing.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 3
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Walk the CastSpell hits — DamageInstance carries .source = CastSpell.
	var hop_indices: Array[int] = []
	for hit in outcome.hits:
		var cs := hit.source as CastSpell
		hop_indices.append(cs.hop_index)
	for i in hop_indices.size() - 1:
		assert_true(hop_indices[i] <= hop_indices[i + 1],
				"hop_index monotonic, got %s" % str(hop_indices))


func test_multiple_on_hit_effects_run_in_order_per_state() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	var a := _RecordingEffect.new()
	a.label = &"A"
	var b := _RecordingEffect.new()
	b.label = &"B"
	var spell := helper.make_spell(NoPropagation.new(), [a, b], 10.0)
	var n := graph.get_skill_nodes()
	SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Single seed state runs effects in array order.
	assert_eq(a.calls.size(), 1)
	assert_eq(b.calls.size(), 1)
