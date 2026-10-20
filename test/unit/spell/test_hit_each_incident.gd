extends GutTest

## `IncidentReducer.hit_each_incident`: several fronts reaching one node in one
## wave each land their own hit — own payload, own crit evaluation, ordered by
## predecessor stable id — while the node still departs once off the merge.

var h: SpellTestHelper


## Crits only the arrival whose payload came from [member from]; records every
## predecessor it was asked about, in evaluation order.
class FromCondition extends LandingCondition:
	var from: SkillNode = null
	var seen: Array[SkillNode] = []

	func evaluate(lctx: LandingContext) -> bool:
		if lctx.payload == null:
			return false
		seen.append(lctx.payload.predecessor)
		return lctx.payload.predecessor == from


func before_each() -> void:
	h = SpellTestHelper.new()


## 0 (attacker) → seed 1 → {2, 3, 4} → 5 → 6. [param fan] lists node 1's
## edges, so the three fronts into 5 are minted in that order.
func _cast(fan: Array, per_incident: bool, bites: float = 0.0) -> Dictionary:
	var adj: Array = [[0, 1]]
	for e in fan:
		adj.append(e)
	adj.append_array([[2, 5], [3, 5], [4, 5], [5, 6]])
	var graph := h.make_graph(adj, self)
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.give_big_hp(atk)
	h.assign_owner(graph, def, [1, 2, 3, 4, 5, 6])
	h.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var reducer := h.sum_reducer()
	reducer.hit_each_incident = per_incident
	var config := h.make_config(h.fan_all(), h.owner_enemy(), reducer, {max_hops = 3})
	if bites > 0.0:
		var scalar := CarriedScalar.new()
		scalar.id = &"bites"
		scalar.seed_value = bites
		config.extensions = [scalar]
		config.repeat_landings_by = &"bites"
	var effects: Array[OnHitEffect] = [DamageEffect.new()]
	if bites > 0.0:
		var rider := ApplyStatusEffect.new()
		rider.def = preload("res://effects/status/sunder.tres")
		effects.push_front(rider)
	var spell := h.make_spell(config, effects, 10.0)
	var n := graph.get_skill_nodes()
	var cond := FromCondition.new()
	cond.from = n[4]
	spell.crit_conditions = [cond]
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	return {graph = graph, n = n, outcome = outcome, cond = cond}


func _hits_on(outcome: AttackOutcome, node: SkillNode) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit.target == node:
			out.append(hit)
	return out


func _events_on(outcome: AttackOutcome, node: SkillNode) -> Array[PropagationEvent]:
	var out: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if ev.target == node and ev.verb != PropagationEvent.Verb.CANCEL:
			out.append(ev)
	return out


const FORWARD := [[1, 2], [1, 3], [1, 4]]
const REVERSED := [[1, 4], [1, 3], [1, 2]]


func test_three_fronts_land_three_hits_each_crit_against_its_own_source() -> void:
	var r := _cast(FORWARD, true)
	var n: Array = r.n
	var outcome: AttackOutcome = r.outcome
	var hits := _hits_on(outcome, n[5])
	assert_eq(hits.size(), 3, "one hit per incident")
	if hits.size() != 3:
		return
	assert_eq(hits.map(func(x): return x.origin), [n[2], n[3], n[4]], "each hit flies from its own front")
	assert_eq(hits[0].crit_tier, 0, "B's hit does not crit")
	assert_eq(hits[1].crit_tier, 0, "C's hit does not crit")
	assert_gte(hits[2].crit_tier, 1, "D's hit crits on its own predecessor")
	var on_5: Array = (r.cond as FromCondition).seen.filter(func(p): return p in [n[2], n[3], n[4]])
	assert_eq(on_5, [n[2], n[3], n[4]], "the crit condition saw each incident once, in order")
	var events := _events_on(outcome, n[5])
	assert_eq(events.size(), 1, "one landing event for the node")
	if events.size() == 1:
		assert_eq(events[0].hits.size(), 3, "the event carries all three hits")
	assert_eq(_hits_on(outcome, n[6]).size(), 1, "the node departs once")


## `repeat_landings_by` composes with the per-incident landing: three incident
## arrivals x two repeats = six landings on the converged node, each incident's
## repeats adjacent and in order. A damage hit carries no key, so the distinct
## `hit_key`s are read off the status rider each landing plants.
func test_per_incident_arrivals_each_repeat_n_times() -> void:
	var r := _cast(FORWARD, true, 2.0)
	var n: Array = r.n
	var hits := _hits_on(r.outcome, n[5])
	var damage := hits.filter(func(x): return x is DamageInstance)
	var keys := {}
	for x in hits:
		if x is StatusInstance:
			keys[x.hit_key] = true
	assert_eq(damage.size(), 6, "3 incidents x 2 repeats")
	assert_eq(keys.size(), 6, "six landings, six distinct hit keys")
	if damage.size() == 6:
		assert_eq(damage.map(func(x): return x.origin),
				[n[2], n[2], n[3], n[3], n[4], n[4]], "each incident's two bites adjacent")


func test_off_keeps_one_merged_hit() -> void:
	var r := _cast(FORWARD, false)
	var n: Array = r.n
	assert_eq(_hits_on(r.outcome, n[5]).size(), 1, "one merged hit, as before")
	assert_eq(_hits_on(r.outcome, n[6]).size(), 1)


func test_hits_follow_stable_id_whatever_the_mint_order() -> void:
	var off_fwd := _cast(FORWARD, false)
	var off_rev := _cast(REVERSED, false)
	var ev_f := _events_on(off_fwd.outcome, off_fwd.n[5])
	var ev_r := _events_on(off_rev.outcome, off_rev.n[5])
	assert_eq(ev_f.size(), 1)
	assert_eq(ev_r.size(), 1)
	if ev_f.size() != 1 or ev_r.size() != 1:
		return
	var idx := func(arr: Array, nodes: Array) -> Array:
		return arr.map(func(p): return nodes.find(p))
	assert_ne(idx.call(ev_f[0].predecessors, off_fwd.n), idx.call(ev_r[0].predecessors, off_rev.n),
			"fixture: the two edge orders mint the fronts in different orders")
	for fan in [FORWARD, REVERSED]:
		var r := _cast(fan, true)
		var n: Array = r.n
		var g: Graph = r.graph
		var hits := _hits_on(r.outcome, n[5])
		var ids: Array = hits.map(func(x): return g.get_stable_id(x.origin))
		var sorted := ids.duplicate()
		sorted.sort()
		assert_eq(hits.size(), 3)
		assert_eq(ids, sorted, "hits in predecessor stable-id order")
		var ev := _events_on(r.outcome, n[5])
		if ev.size() == 1:
			assert_eq(ev[0].predecessors, hits.map(func(x): return x.origin),
					"the event's predecessors align with its hits")


func test_record_round_trips_three_hits_on_one_node_in_one_wave() -> void:
	var r := _cast(FORWARD, true)
	var n: Array = r.n
	var g: Graph = r.graph
	var outcome: AttackOutcome = r.outcome
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, g), g)
	var before := _hits_on(outcome, n[5])
	var after := _hits_on(rebuilt, n[5])
	assert_eq(after.size(), 3, "three hits survive the record")
	if after.size() != before.size():
		return
	for i in before.size():
		assert_eq(after[i].origin, before[i].origin, "hit %d origin" % i)
		assert_almost_eq(after[i].amount, before[i].amount, 0.0001, "hit %d amount" % i)
		assert_eq(after[i].crit_tier, before[i].crit_tier, "hit %d crit tier" % i)
		assert_eq(after[i].is_crit, before[i].is_crit, "hit %d crit" % i)
	var ev := _events_on(rebuilt, n[5])
	assert_eq(ev.size(), 1)
	if ev.size() == 1:
		assert_eq(ev[0].hits.size(), 3, "the rebuilt event carries the three hits")
