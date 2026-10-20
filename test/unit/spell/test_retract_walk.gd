extends GutTest

## Lodestone's out-and-back walk without its haul: RetractSpread's phase timing
## (OUT as BFS, dead ends hopping in place, every return in sync), the trail
## map RetractFront records at OUT, the proportional largest-remainder split on
## the way back, RetractReducer's waiting-beats-incoming guard and PhaseCondition.

const _POISON := preload("res://effects/status/poison.tres")

var h: SpellTestHelper


## Logs every landing: node, wave, phase, incident count and the cargo it carries.
class Recorder extends OnHitEffect:
	var rows: Array = []

	func apply(landing: HitLanding) -> void:
		var lctx := landing as LandingContext
		var st := RetractFront.state_of(lctx.payload)
		var cargo: Array = []
		for piece: RetractFront.Piece in st.cargo:
			cargo.append([piece.from, piece.def.id, piece.amount])
		rows.append({node = lctx.node, wave = lctx.cast.wave_index, phase = st.phase,
				incidents = lctx.incidents.size(), cargo = cargo, walk = st.walk})


func before_each() -> void:
	h = SpellTestHelper.new()


## 0 (attacker) → seed 1 → the tree in [param adj]; the defender owns every
## other node, each holding [param poison] (per index, default 1).
func _cast(adj: Array, poison: Dictionary = {}, effects: Array[OnHitEffect] = []) -> Dictionary:
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
	for i in range(1, n.size()):
		var stacks: float = poison.get(i, 1.0)
		if stacks > 0.0:
			CombatWorld.live().combat_for(n[i]).apply_status(_POISON, stacks)
	var spread := RetractSpread.new()
	spread.depth = 3
	var config := h.make_config(spread, h.owner_enemy(), RetractReducer.new(), {max_hops = 99})
	config.extensions = [RetractFront.new()]
	var rec := Recorder.new()
	var on_hits: Array[OnHitEffect] = [rec]
	on_hits.append_array(effects)
	var spell := h.make_spell(config, on_hits, 0.0)
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	return {n = n, rows = rec.rows, outcome = outcome}


func _rows_on(rows: Array, node: SkillNode) -> Array:
	return rows.filter(func(r: Dictionary) -> bool: return r.node == node)


func _waves(rows: Array, phase: RetractFront.Phase) -> Array:
	return rows.filter(func(r: Dictionary) -> bool: return r.phase == phase) \
			.map(func(r: Dictionary) -> int: return r.wave)


# 1 seed; 2 dead-ends at depth 1; 3 → 4 → 5 reaches depth 3.
const TREE := [[0, 1], [1, 2], [1, 3], [3, 4], [4, 5]]


func test_walk_timing_out_wait_turn_back() -> void:
	var r := _cast(TREE)
	var n: Array = r.n
	var rows: Array = r.rows
	var out_wave := {}
	for row: Dictionary in rows:
		if row.phase == RetractFront.Phase.OUT:
			out_wave[n.find(row.node)] = row.wave
	assert_eq(out_wave, {1: 0, 2: 1, 3: 1, 4: 2, 5: 3}, "OUT is a BFS: depth k lands on wave k")
	var dead := _rows_on(rows, n[2])
	assert_eq(dead.map(func(row: Dictionary) -> int: return row.wave), [1, 2, 3, 4, 5, 6],
			"the dead end lands OUT, then hops in place 2·(3−1)+1 = 5 times")
	assert_eq(dead.map(func(row: Dictionary) -> int: return row.phase), [
			RetractFront.Phase.OUT, RetractFront.Phase.WAIT, RetractFront.Phase.WAIT,
			RetractFront.Phase.WAIT, RetractFront.Phase.WAIT, RetractFront.Phase.BACK],
			"its last in-place hop is the turn")
	assert_eq(_waves(_rows_on(rows, n[5]), RetractFront.Phase.BACK), [4], "the rim turns on wave 4")
	assert_eq(_waves(_rows_on(rows, n[4]), RetractFront.Phase.BACK), [5])
	assert_eq(_waves(_rows_on(rows, n[3]), RetractFront.Phase.BACK), [6])
	var seed_back := _rows_on(rows, n[1]).filter(
			func(row: Dictionary) -> bool: return row.phase == RetractFront.Phase.BACK)
	assert_eq(seed_back.size(), 1, "both branches merge into one BACK landing on the seed")
	if seed_back.size() == 1:
		assert_eq(seed_back[0].wave, 7, "the seed's BACK is wave 2·depth+1")
		assert_eq(seed_back[0].incidents, 2, "one return from each branch")
	var last := 0
	for row: Dictionary in rows:
		last = maxi(last, row.wave)
	assert_eq(last, 7, "the resolve ends at the seed")


func test_back_cargo_names_what_each_node_passes_to_its_parent() -> void:
	var r := _cast(TREE)
	var n: Array = r.n
	var back4 := _rows_on(r.rows, n[4]).filter(
			func(row: Dictionary) -> bool: return row.phase == RetractFront.Phase.BACK)
	assert_eq(back4.size(), 1)
	if back4.size() == 1:
		assert_eq(back4[0].cargo, [[n[5], &"poison", 1]], "the rim's poison rides back to its parent")


# T=1 → A2, B3, C4; A→D5, B→E6, C→E6; D→F7, E→F7. Trails D 1, E 2, F 3.
const DIAMOND := [[0, 1], [1, 2], [1, 3], [1, 4], [2, 5], [3, 6], [4, 6], [5, 7], [6, 7]]


func test_diamond_trails_and_proportional_split() -> void:
	var r := _cast(DIAMOND, {6: 2.0, 7: 3.0})
	var n: Array = r.n
	var walk: RetractFront.Walk = r.rows[0].walk
	assert_eq([walk.trails_of(n[5]), walk.trails_of(n[6]), walk.trails_of(n[7])], [1, 2, 3],
			"BFS path counts: D 1, E 2, F 3")
	var back := func(i: int) -> Array:
		return _rows_on(r.rows, n[i]).filter(
				func(row: Dictionary) -> bool: return row.phase == RetractFront.Phase.BACK)
	var at_d: Array = back.call(5)
	var at_e: Array = back.call(6)
	assert_eq(at_d[0].cargo if at_d.size() > 0 else [], [[n[7], &"poison", 1]], "F's 3 split D:E = 1:2")
	assert_eq(at_e[0].cargo if at_e.size() > 0 else [], [[n[7], &"poison", 2]])
	var at_b: Array = back.call(3)
	var at_c: Array = back.call(4)
	assert_eq(at_b[0].cargo if at_b.size() > 0 else [], [[n[6], &"poison", 1]], "E's 2 split B:C evenly")
	assert_eq(at_c[0].cargo if at_c.size() > 0 else [], [[n[6], &"poison", 1]])


func _payload(phase: RetractFront.Phase, front: RetractFront, cargo: Array = []) -> CastSpell:
	var p := CastSpell.blank()
	var st := front.seed(PropagationContext.new()) as RetractFront.State
	st.phase = phase
	for c: Array in cargo:
		st.cargo.append(RetractFront.Piece.of(c[0], c[1], c[2]))
	p.extras.append(st)
	return p


func test_waiting_meets_incoming_the_wait_continues_and_the_back_is_cancelled() -> void:
	var front := RetractFront.new()
	var incoming := _payload(RetractFront.Phase.BACK, front, [[null, _POISON, 3]])
	var waiting := _payload(RetractFront.Phase.WAIT, front)
	var incidents: Array[CastSpell] = [incoming, waiting]
	var merged := RetractReducer.new().reduce(incidents, PropagationContext.new())
	assert_not_null(merged)
	var st := RetractFront.state_of(merged) if merged != null else null
	assert_eq(st.phase if st != null else -1, RetractFront.Phase.WAIT, "the in-place tendril continues")
	assert_eq(st.cargo.size() if st != null else -1, 0, "the incoming one's cargo never moves")


func test_returns_merging_at_one_node_concatenate_their_cargo() -> void:
	var front := RetractFront.new()
	var a := _payload(RetractFront.Phase.BACK, front, [[null, _POISON, 2]])
	var b := _payload(RetractFront.Phase.BACK, front, [[null, _POISON, 3]])
	var incidents: Array[CastSpell] = [a, b]
	var st := RetractFront.state_of(RetractReducer.new().reduce(incidents, PropagationContext.new()))
	assert_eq(st.phase, RetractFront.Phase.BACK)
	assert_eq(st.cargo.map(func(p: RetractFront.Piece) -> int: return p.amount), [2, 3])


func test_phase_condition_reads_the_payload_phase() -> void:
	var front := RetractFront.new()
	var cond := PhaseCondition.new()
	cond.phase = RetractFront.Phase.BACK
	assert_true(cond.evaluate(LandingContext.for_test(_payload(RetractFront.Phase.BACK, front))))
	assert_false(cond.evaluate(LandingContext.for_test(_payload(RetractFront.Phase.OUT, front))))
	assert_false(cond.evaluate(LandingContext.for_test(CastSpell.blank())), "no front: false")


func test_a_gated_effect_runs_only_on_its_phase() -> void:
	var gated := Recorder.new()
	var cond := PhaseCondition.new()
	cond.phase = RetractFront.Phase.OUT
	gated.when = cond
	var r := _cast(TREE, {}, [gated])
	assert_eq(gated.rows.size(), 5, "one OUT landing per node")
	assert_true(gated.rows.all(func(row: Dictionary) -> bool: return row.phase == RetractFront.Phase.OUT))
	assert_gt(r.rows.size(), 5)


func test_unauthored_outbound_fallback_never_lands_in_the_export() -> void:
	var spread := RetractSpread.new()
	assert_not_null(spread._outbound(), "an unauthored spread still fans")
	assert_null(spread.outbound_spread, "the fallback is not written into the @export")
