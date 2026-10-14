@tool
extends GutTest

## Demon Bell (`reverberator.tres`) rings corruption: an innate corruption
## affinity lands on every landing, and a self-loop landing's condition crit
## doubles it. The rung pile topples into the node's friendly neighbours.
## Every number is read from the def's exports and the attacker's board.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _REVERBERATOR: SpellDef = preload("res://attack/spell/defs/reverberator.tres")
const _CORRUPTION: StatusDef = preload("res://effects/status/corruption.tres")


## 0(atk) - 1(self-loop, D) - {2, 3} (D), 2 - 3, both - 4 (D's core): a core
## never topples, so the rung node is not it, and 2 and 3 are no leaves (a
## leaf's `T` is 2, so it drains everything it is given). The degree filter keeps every
## ring on node 1; 2 and 3 are its friendly neighbours.
func _setup() -> Dictionary:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1], [1, 2], [1, 3], [2, 3], [2, 4], [3, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [4, 1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	return {graph = graph, atk = atk, n = graph.get_skill_nodes()}


func _intake() -> AspectIntake:
	for a in _REVERBERATOR.intakes:
		if a != null and a.aspect_id() == _CORRUPTION.identity.id:
			return a
	return null


## Corruption riders landed on [param node], in landing order.
func _corruption_on(outcome: AttackOutcome, node: SkillNode) -> Array[StatusInstance]:
	var out: Array[StatusInstance] = []
	for hit in outcome.hits:
		if hit is StatusInstance and hit.target == node and hit.def != null \
				and hit.def.id == _CORRUPTION.id:
			out.append(hit)
	return out


func _cast(s: Dictionary, infusion: Infusion = null) -> AttackOutcome:
	var n: Array = s.n
	return SpellResolver.resolve(_REVERBERATOR, n[1], n[0], s.atk, s.graph, null, infusion)


func test_the_spell_carries_a_corruption_intake() -> void:
	var a := _intake()
	assert_not_null(a, "reverberator lists a corruption affinity")
	if a != null:
		assert_gt(a.innate, 0, "it rings corruption with no infusion")


func test_seed_landing_adds_innate_plus_the_attackers_stacks_stat() -> void:
	var a := _intake()
	assert_not_null(a, "corruption affinity")
	if a == null:
		return
	var s := _setup()
	var stat: Stat = (s.atk as Entity).stat_board.get_stat(&"corruption_stacks_per_hit")
	assert_not_null(stat, "the attacker's board carries corruption_stacks_per_hit")
	var plain := _corruption_on(_cast(s), s.n[1])
	assert_gt(plain.size(), 0, "the seed lands corruption")
	if plain.is_empty():
		return
	assert_eq(plain[0].power, float(a.innate), "seed = innate")
	if stat == null:
		return
	var extra := 2.0
	stat.base_value = stat.base_value + extra
	var boosted := _corruption_on(_cast(s), s.n[1])
	assert_gt(boosted.size(), 0, "the seed lands corruption")
	if not boosted.is_empty():
		assert_eq(boosted[0].power, float(a.innate) + extra, "seed = innate + stacks_per_hit")


func test_a_self_loop_landing_lands_crit_multiplier_times_the_seed() -> void:
	var s := _setup()
	var landed := _corruption_on(_cast(s), s.n[1])
	var hops := int((_REVERBERATOR.propagation as PropagationConfig).max_hops)
	assert_eq(landed.size(), 1 + hops, "seed + one ring per hop")
	if landed.size() < 2:
		return
	var cm := CritRoll.multiplier_for((s.atk as Entity).stat_board)
	for i in range(1, landed.size()):
		assert_eq(landed[i].power, StatusDef.round_half_up(landed[0].power * cm),
				"ring %d = crit_multiplier × seed" % i)


func test_a_corruption_infusion_raises_the_seed_by_its_rate() -> void:
	var a := _intake()
	assert_not_null(a, "corruption affinity")
	if a == null:
		return
	var s := _setup()
	var p := 3
	var infusion := Infusion.for_cast(_REVERBERATOR, {a.aspect_id(): p})
	var landed := _corruption_on(_cast(s, infusion), s.n[1])
	assert_gt(landed.size(), 0, "the seed lands corruption")
	if not landed.is_empty():
		assert_eq(landed[0].power, float(a.innate + floori(p * float(a.affinity_gain) / a.affinity_cost)), "seed = innate + floor(p × affinity)")


func test_ringing_a_self_loop_topples_into_the_friendly_neighbours() -> void:
	var s := _setup()
	var n: Array = s.n
	var world := CombatWorld.shadow()
	var outcome := SpellResolver.resolve_against(_REVERBERATOR, n[1], n[0], s.atk, s.graph, world)
	var bursts := 0
	for hit in outcome.hits:
		for op: CombatWorld.SettleOp in hit.settle:
			# A burst op: no receiver, the host's `T` stamped (a transfer has a `to`).
			if op.to == null and op.threshold > 0 and op.from == (n[1] as SkillNode).get_combat() \
					and op.def != null and op.def.id == _CORRUPTION.id:
				bursts += int(op.amount)
	assert_gt(bursts, 0, "the rung node toppled at least once within the cast")
	for i in [2, 3]:
		assert_gte(world.combat_for(n[i]).get_status_power(_CORRUPTION.id), 1.0,
				"friendly neighbour %d holds the stain" % i)
	var rule := _CORRUPTION.spread as SandpileSpread
	var field := StackField.over_world(_CORRUPTION, rule.ownership_mask, world, [n[1]] as Array[SkillNode], s.graph)
	var host := world.combat_for(n[1])
	assert_lt(int(host.get_status_power(_CORRUPTION.id)), rule.threshold(field, host),
			"the leftover pile settled below T")
	world.free_shadow()
