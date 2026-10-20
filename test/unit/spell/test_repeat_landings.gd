extends GutTest

## `PropagationConfig.repeat_landings_by`: a landing hits as many times as the
## named CarriedScalar says, each repeat its own payload, hit_key and crit,
## landing in order — so a later bite sees an earlier bite's Sunder, and an
## in-place damage scale never compounds across bites.

const _SUNDER := preload("res://effects/status/sunder.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _bites(seed_value: float) -> CarriedScalar:
	var s := CarriedScalar.new()
	s.id = &"bites"
	s.seed_value = seed_value
	s.progression = h.flat_add_progression(-1.0)
	s.min_value = 1.0
	return s


func _sunder() -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.def = _SUNDER
	return e


## 0 (attacker) → seed 1 → … along [param adj]; the defender owns every other
## node. [param effects] are the spell's on-hits.
func _cast(adj: Array, effects: Array[OnHitEffect], bites: float,
		opts: Dictionary = {}, armor: float = 0.0) -> Dictionary:
	var graph := h.make_graph(adj, self)
	var n := graph.get_skill_nodes()
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.give_big_hp(atk)
	var owned: Array = []
	for i in range(1, n.size()):
		owned.append(i)
	h.assign_owner(graph, def, owned)
	h.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	if armor != 0.0:
		_set_armor(n[1], armor)
	var config := h.make_config(h.fan_all(), h.owner_enemy(), null, opts)
	config.extensions = [_bites(bites)]
	config.repeat_landings_by = &"bites" if opts.get("repeat", true) else &""
	var spell := h.make_spell(config, effects, 10.0)
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	return {graph = graph, n = n, outcome = outcome}


func _set_armor(node: SkillNode, value: float) -> void:
	var cur := float(CombatWorld.live().combat_for(node).get_local_value(&"armor"))
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value - cur
	node.add_local_modifier(m)


func _hits_on(outcome: AttackOutcome, node: SkillNode) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit.target == node:
			out.append(hit)
	return out


func _damage_on(outcome: AttackOutcome, node: SkillNode) -> Array[HitInstance]:
	return _hits_on(outcome, node).filter(func(x): return x is DamageInstance)


func _event_on(outcome: AttackOutcome, node: SkillNode) -> PropagationEvent:
	for ev in outcome.timeline:
		if ev.target == node:
			return ev
	return null


const LINE := [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]]


func test_bites_step_down_the_walk_and_the_zero_hop_is_terminal() -> void:
	var r := _cast(LINE, [_sunder(), DamageEffect.new()], 3.0, {max_hops = 5})
	var n: Array = r.n
	var counts := [1, 2, 3, 4].map(func(i): return _damage_on(r.outcome, n[i]).size())
	assert_eq(counts, [3, 2, 1, 0], "seed 3, −1/hop: 3, 2, 1 bites, then none")
	var last := _event_on(r.outcome, n[4])
	assert_not_null(last, "the zero-bite hop still lands")
	if last != null:
		assert_true(last.is_terminal, "and the walk ends there")
	assert_null(_event_on(r.outcome, n[5]), "nothing past it")


func test_each_bite_lands_its_status_before_its_damage_under_its_own_key() -> void:
	var r := _cast(LINE, [_sunder(), DamageEffect.new()], 3.0, {max_hops = 0})
	var hits := _hits_on(r.outcome, r.n[1])
	assert_eq(hits.map(func(x): return x is DamageInstance), [false, true, false, true, false, true],
			"status, damage per bite, bite by bite")
	var keys := {}
	for hit in hits:
		if hit is StatusInstance:
			keys[hit.hit_key] = true
	assert_eq(keys.size(), 3, "three bites, three distinct keys")


func test_each_bite_sees_the_sunder_the_bite_before_it_landed() -> void:
	var r := _cast(LINE, [_sunder(), DamageEffect.new()], 3.0, {max_hops = 0}, 6.0)
	var dmg := _damage_on(r.outcome, r.n[1])
	assert_eq(dmg.size(), 3)
	if dmg.size() != 3:
		return
	assert_gte(dmg[1].effective_amount, dmg[0].effective_amount, "bite 2 lands on less armor than bite 1")
	assert_gte(dmg[2].effective_amount, dmg[1].effective_amount, "bite 3 on less than bite 2")
	assert_gt(dmg[2].effective_amount, dmg[0].effective_amount, "the ramp is real, not flat")


func test_a_later_wave_sees_an_earlier_waves_sunder() -> void:
	# 1 ↔ 2, two visits each: node 1 bitten at hop 0 (3 bites) and again at hop 2.
	var r := _cast([[0, 1], [1, 2]], [_sunder(), DamageEffect.new()], 3.0,
			{max_hops = 2, max_visits_per_node = 2}, 6.0)
	var dmg := _damage_on(r.outcome, r.n[1])
	assert_eq(dmg.size(), 4, "3 bites at hop 0, 1 at hop 2")
	if dmg.size() != 4:
		return
	assert_gt(dmg[3].effective_amount, dmg[0].effective_amount, "hop 2's bite meets hop 0's Sunder")


func test_an_in_place_damage_scale_does_not_compound_across_bites() -> void:
	var scale := ScaleDamageEffect.new()
	var scaled := _cast(LINE, [scale, DamageEffect.new()], 3.0, {max_hops = 0})
	var plain := _cast(LINE, [DamageEffect.new()], 1.0, {max_hops = 0})
	var dmg := _damage_on(scaled.outcome, scaled.n[1])
	var base := _damage_on(plain.outcome, plain.n[1])
	assert_eq(dmg.size(), 3)
	assert_eq(base.size(), 1)
	if dmg.size() != 3 or base.size() != 1:
		return
	for hit in dmg:
		assert_almost_eq(hit.amount, scale.factor * base[0].amount, 0.001,
				"every bite is one scale of the base, never a scale of the last bite")


func test_empty_keeps_one_landing() -> void:
	var r := _cast(LINE, [DamageEffect.new()], 3.0, {max_hops = 0, repeat = false})
	assert_eq(_damage_on(r.outcome, r.n[1]).size(), 1, "no repeat_landings_by: one landing, bites or not")
