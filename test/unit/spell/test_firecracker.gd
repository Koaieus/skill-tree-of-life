extends GutTest

## Firecracker (#1400): every landing is a blast whose radius shrinks with the
## fuel the cast burns per wave, and every hostile node inside it is where the
## next wave lands. Geometry is derived from the shipped knobs, never literals.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const FIRECRACKER: SpellDef = preload("res://attack/spell/defs/firecracker.tres")
const _EXPLOSIVE_STATUS := preload("res://effects/status/explosive.tres")
const _POISON := &"poison"

var h: SpellTestHelper
var reach: FuelBlastReach
var load_: Dictionary
## Index 0 is always the attacker's node, far away unless a test moves it.
const FAR := Vector2(-100000, 0)


func before_each() -> void:
	h = H.new()
	reach = FIRECRACKER.propagation.reach as FuelBlastReach
	load_ = Infusion.innate(FIRECRACKER).load_of(FIRECRACKER)


func _r(hop: int, load: Dictionary = load_) -> float:
	return reach.radius_at(load, hop)


## A graph of [param positions] (index -> Vector2; index 0 the attacker's).
## [param edges] are the only edges besides each node's tether to node 0,
## which only exists so every node is minted. Every node but 0 and
## [param friendly] is hostile.
func _board(positions: Dictionary, edges: Array = [], friendly: Array = []) -> Dictionary:
	var adj: Array = []
	for i in positions:
		if i != 0:
			adj.append([0, i])
	adj.append_array(edges)
	var pos := positions.duplicate()
	if not pos.has(0):
		pos[0] = FAR
	var graph := h.make_graph(adj, self, pos)
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.give_big_hp(atk)
	var hostile: Array = []
	for i in positions:
		if i != 0 and not friendly.has(i):
			hostile.append(i)
	h.assign_owner(graph, def, hostile)
	h.assign_owner(graph, atk, [0] + friendly)
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	return {graph = graph, atk = atk, n = graph.get_skill_nodes()}


func _resolve(b: Dictionary, seed_idx: int, spell: SpellDef = FIRECRACKER, inf: Infusion = null) -> AttackOutcome:
	var n: Array = b.n
	return SpellResolver.resolve(spell, n[seed_idx], n[0], b.atk, b.graph, null, inf)


func _landings(outcome: AttackOutcome) -> Array[PropagationEvent]:
	var out: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if ev.verb != PropagationEvent.Verb.CANCEL:
			out.append(ev)
	return out


func _beats_of(outcome: AttackOutcome, node: SkillNode) -> Array:
	return _landings(outcome).filter(func(ev): return ev.target == node).map(func(ev): return ev.beat)


func _hits_on(outcome: AttackOutcome, node: SkillNode) -> Array:
	return outcome.hits.filter(func(x): return _is_main_hit(x, node))


func _is_main_hit(x: HitInstance, node: SkillNode) -> bool:
	return x.target == node and not (x is CureInstance or x is StatusInstance or x is PairedDamageInstance)


func _rad() -> float:
	return 32.0


## A distance whose disc-touching reach lies strictly between hop k+1's and
## hop k's radii: reached at hop k, not at k+1.
func _between(k: int, rad: float, load: Dictionary = load_) -> float:
	return rad + 0.5 * (_r(k, load) + _r(k + 1, load))


# 1 ---------------------------------------------------------------------------

func test_a_landing_reaches_every_hostile_in_its_blast_edge_or_no_edge() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(0.5 * _r(0), 0), 3: Vector2(-0.5 * _r(0), 0)})
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	assert_eq(_beats_of(outcome, n[2]), [1], "Y lands on wave 1")
	assert_eq(_beats_of(outcome, n[3]), [1], "Z lands on wave 1")


func test_candidates_exclude_the_landed_node_in_stable_id_order() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(0.5 * _r(0), 0), 3: Vector2(-0.5 * _r(0), 0)})
	var n: Array = b.n
	var lctx := _lctx(b, n[1], 0)
	var got := reach.candidates(lctx)
	assert_false(got.has(n[1]), "never the landed node")
	assert_true(got.has(n[2]) and got.has(n[3]), "both blast targets")
	var ids: Array = got.map(func(x): return (b.graph as Graph).get_stable_id(x))
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted, "stable-id order")


func _lctx(b: Dictionary, node: SkillNode, hop: int, damage: float = 1.0, load: Dictionary = load_) -> LandingContext:
	var cast := PropagationContext.new()
	cast.graph = b.graph
	cast.caster = b.atk
	cast.load.assign(load)
	var payload := CastSpell.new()
	payload.current_node = node
	payload.hop_index = hop
	payload.damage = damage
	return LandingContext.for_test(payload, node, cast)


# 2 ---------------------------------------------------------------------------

func test_a_node_reached_at_fuel_f_is_out_of_reach_at_the_next_fuel() -> void:
	var k := 1
	var b := _board({1: Vector2.ZERO, 2: Vector2(_between(k, _rad()), 0)})
	var n: Array = b.n
	assert_true(reach.candidates(_lctx(b, n[1], k)).has(n[2]), "inside hop k's blast")
	assert_false(reach.candidates(_lctx(b, n[1], k + 1)).has(n[2]), "outside hop k+1's blast")


# 3 ---------------------------------------------------------------------------

func test_the_cast_ends_when_the_fuel_runs_out() -> void:
	var last := int(load_.get(reach.fuel_aspect, 0)) / reach.fuel_per_jump
	assert_lt(last, int(FIRECRACKER.propagation.max_hops), "fixture: fuel, not hops, binds")
	assert_eq(_r(last), 0.0, "fixture: no blast at fuel 0")
	var step := _r(last - 1) + 0.5 * _rad()
	var pos := {}
	for i in range(1, 80):
		pos[i] = Vector2((i - 1) * step, 0)
	var b := _board(pos)
	var outcome := _resolve(b, 1)
	var beats: Array = _landings(outcome).map(func(ev): return ev.beat)
	assert_eq(beats.max(), last, "the last wave lands at fuel 0 and goes nowhere")
	assert_true(_beats_of(outcome, b.n[79]).is_empty(), "fixture: the chain outruns the fuel")


func test_with_ample_fuel_the_cast_stops_at_max_hops() -> void:
	var hops := int(FIRECRACKER.propagation.max_hops)
	var inf := Infusion.for_cast(FIRECRACKER, {reach.fuel_aspect: 100})
	var load := inf.load_of(FIRECRACKER)
	var step := 0.75 * reach.max_radius
	assert_gte(_r(hops, load), step - _rad(), "fixture: fuel still reaches at max_hops")
	assert_lt(_r(0, load), 2.0 * step - _rad(), "fixture: one node per wave")
	var pos := {}
	for i in range(1, hops + 4):
		pos[i] = Vector2((i - 1) * step, 0)
	var b := _board(pos)
	var outcome := _resolve(b, 1, FIRECRACKER, inf)
	var beats: Array = _landings(outcome).map(func(ev): return ev.beat)
	assert_eq(beats.max(), hops, "the cast stops at max_hops")


# 4 ---------------------------------------------------------------------------

func test_two_nodes_across_a_gap_never_trade_hits() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(0.5 * _r(1), 0)})
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	assert_eq(_beats_of(outcome, n[1]), [0], "the seed lands once")
	assert_eq(_beats_of(outcome, n[2]), [1], "its neighbour across the gap once")


func test_no_node_lands_in_two_waves() -> void:
	var pos := {}
	for i in range(1, 30):
		pos[i] = Vector2((i % 6) * 0.3 * _r(2), (i / 6) * 0.3 * _r(2))
	var b := _board(pos)
	var outcome := _resolve(b, 1)
	for node in b.n:
		assert_lte(_beats_of(outcome, node).size(), 1, "%s lands at most once" % node.name)


# 5 ---------------------------------------------------------------------------

func test_a_friendly_node_inside_the_blast_never_lands() -> void:
	var b := _board({1: Vector2.ZERO, 2: Vector2(0.5 * _r(0), 0), 3: Vector2(0, 0.5 * _r(0))}, [], [3])
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	assert_eq(_beats_of(outcome, n[2]), [1], "the hostile lands")
	assert_true(_beats_of(outcome, n[3]).is_empty(), "the friendly never does")


# 6, 7, 10 --------------------------------------------------------------------

## Seed S(1); B(2), C(3), D(4) inside S's blast; A(5) outside S's blast but
## inside each of theirs; B and C share an edge with A, D does not. E(6) sits
## where only a hop-2 blast from A reaches it.
func _three_blasts(extra: Dictionary = {}) -> Dictionary:
	var rad := _rad()
	var hx := 0.5 * _r(0)
	var ax := hx + _r(1)
	var pos := {1: Vector2.ZERO, 2: Vector2(hx, -8), 3: Vector2(hx, 8), 4: Vector2(hx, 0),
			5: Vector2(ax, 0), 6: Vector2(ax + _between(2, rad), 0)}
	for i in extra:
		pos[i] = Vector2(ax, 0) + (extra[i] as Vector2)
	var b := _board(pos, [[2, 5], [3, 5]])
	assert_gt(ax - rad, _r(0), "fixture: A outside the seed's blast")
	return b


func test_three_blasts_hit_a_three_times_only_the_gap_jump_crits_and_a_departs_once() -> void:
	var b := _three_blasts()
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	var on_a := _hits_on(outcome, n[5])
	assert_eq(on_a.size(), 3, "one hit per covering blast")
	for hit in on_a:
		if hit.origin == n[4]:
			assert_gte(hit.crit_tier, 1, "D's blast jumped a gap: crit")
		else:
			assert_eq(hit.crit_tier, 0, "%s shares an edge with A: no crit" % hit.origin.name)
	assert_eq(_beats_of(outcome, n[5]), [2], "A lands once")
	assert_eq(_hits_on(outcome, n[6]).size(), 1, "A departs once")


func test_the_seed_never_crits() -> void:
	var b := _three_blasts()
	var n: Array = b.n
	var outcome := _resolve(b, 1)
	var on_seed := _hits_on(outcome, n[1])
	assert_eq(on_seed.size(), 1)
	for hit in on_seed:
		assert_eq(hit.crit_tier, 0, "no predecessor, no crit")


func test_merged_fronts_depart_with_their_wave_fuel_under_any_reducer() -> void:
	for reducer in [h.max_reducer(), h.sum_reducer(), h.first_reducer()]:
		reducer.hit_each_incident = true
		var spell := FIRECRACKER.duplicate() as SpellDef
		spell.propagation = FIRECRACKER.propagation.duplicate() as PropagationConfig
		spell.propagation.reducer = reducer
		var b := _three_blasts()
		var n: Array = b.n
		var outcome := _resolve(b, 1, spell)
		assert_eq(_beats_of(outcome, n[6]), [3], "%s: A departs on hop-2 fuel" % reducer.get_script().get_global_name())
	var b2 := _three_blasts()
	var nn: Array = b2.n
	assert_eq(reach.candidates(_lctx(b2, nn[5], 2, 1.0)), reach.candidates(_lctx(b2, nn[5], 2, 99.0)),
			"fuel reads the wave, never the front's damage")


# 8, 9 ------------------------------------------------------------------------

func test_a_cast_over_uncharged_nodes_plants_nothing() -> void:
	var b := _three_blasts()
	var outcome := _resolve(b, 1)
	for hit in outcome.hits:
		if hit is StatusInstance:
			assert_ne(hit.def.id, &"explosive", "fuel never plants")
	assert_false(outcome.hits.any(func(x): return x is CureInstance), "nothing to set off")


func test_a_charged_node_pops_once_per_wave_and_its_blast_carries_poison() -> void:
	var b := _three_blasts({7: Vector2(0, -(2.0 * _rad() + 8.0))})
	var n: Array = b.n
	var a: SkillNode = n[5]
	var spread := _EXPLOSIVE_STATUS.spread as ExplosiveSpread
	assert_gt(spread.radius_for(n[7].radius, 2), 2.0 * _rad() + 8.0 - n[7].radius, "fixture: G inside A's pop")
	a.get_combat().apply_status(_EXPLOSIVE_STATUS, 2.0)
	var inf := Infusion.for_cast(FIRECRACKER, {_POISON: 2})
	var outcome := _resolve(b, 1, FIRECRACKER, inf)
	var cures := outcome.hits.filter(func(x): return x is CureInstance and x.target == a)
	assert_eq(cures.size(), 1, "three hits, one pop")
	assert_eq(_hits_on(outcome, a).size(), 3, "fixture: A took three hits")
	var a_ev: Array = _landings(outcome).filter(func(ev): return ev.target == a)
	assert_eq(a_ev.size(), 1)
	if a_ev.size() != 1:
		return
	var blast_poison: Array = (a_ev[0] as PropagationEvent).hits.filter(
			func(x): return x is StatusInstance and x.def.id == _POISON and x.target != a)
	assert_false(blast_poison.is_empty(), "the pop's blast carries poison outward")
