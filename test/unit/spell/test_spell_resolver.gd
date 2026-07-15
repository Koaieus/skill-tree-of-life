extends GutTest

## SpellResolver: the wave-based BFS driver. Should null-guard, emit hits
## in hop-monotonic order (VFX layer staggers off this), and run every
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
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 3})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
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
	# Single-target via NoStep + max_hops 0.
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [a, b], 10.0)
	var n := graph.get_skill_nodes()
	SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(a.calls.size(), 1)
	assert_eq(b.calls.size(), 1)


func _line_outcome() -> Array:
	# Line 0(atk) - 1(seed) - 2 - 3, fan_all enemy-only, max_hops 2.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	return [SpellResolver.resolve(spell, n[1], n[0], atk, graph), n]


func test_timeline_mirrors_hits_and_shares_damage_refs() -> void:
	# Every damage-bearing landing gets exactly one event; the event's
	# `damage` is the SAME DamageInstance object that's in `hits` (shared, not
	# copied) — that identity is what keeps the additive timeline in sync.
	var res := _line_outcome()
	var outcome: AttackOutcome = res[0]
	assert_eq(outcome.timeline.size(), outcome.hits.size(),
			"one event per hit on a no-cancel line graph")
	for ev in outcome.timeline:
		assert_true(outcome.hits.has(ev.damage),
				"event.damage is a shared ref into hits, not a copy")


func test_seed_stamps_jump_hops_stamp_edge() -> void:
	var res := _line_outcome()
	var outcome: AttackOutcome = res[0]
	var n: Array = res[1]
	var by_target: Dictionary = {}
	for ev in outcome.timeline:
		by_target[ev.target] = ev
	assert_eq(by_target[n[1]].verb, PropagationEvent.Verb.JUMP, "seed = JUMP (a)")
	assert_eq(by_target[n[1]].beat, 0, "seed beat 0")
	assert_eq(by_target[n[2]].verb, PropagationEvent.Verb.EDGE, "hop = EDGE (b)")
	assert_eq(by_target[n[2]].origin, n[1], "hop origin = predecessor")


func test_cancel_folds_into_timeline_as_null_damage_event() -> void:
	# Diamond 1→{2,3}→4 with CancelIfMulti: node 4 fizzles. A CANCEL event
	# lands on the timeline (damage null) AND `cancellations` still records it.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3, 4])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(),
			helper.cancel_if_multi(), {max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var cancels: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if ev.verb == PropagationEvent.Verb.CANCEL:
			cancels.append(ev)
	assert_eq(cancels.size(), 1, "one CANCEL event on the timeline")
	assert_eq(cancels[0].target, n[4], "CANCEL at the fizzled node")
	assert_null(cancels[0].damage, "CANCEL carries no damage")
	assert_eq(outcome.cancellations.size(), 1, "replay projection still populated")


func test_zero_damage_utility_landing_still_emits_event() -> void:
	# base_damage 0 → DamageEffect appends no hit, but the probe must still
	# render its path, so the landing gets an event with null damage.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 0.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 0, "zero-damage landing appends no hit")
	assert_eq(outcome.timeline.size(), 1, "but still emits a probe event")
	assert_null(outcome.timeline[0].damage, "event carries no damage")
