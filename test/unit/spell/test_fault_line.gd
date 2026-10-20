extends GutTest

## Fault Line's parts: the hop gate on its intake load ([HopIndexCondition]),
## the crack's re-read at each arrival ([StatusShareReseed] on a
## [CarriedScalar]) and the status landing that takes its power from that
## carried value ([member ApplyStatusEffect.power_from]). Ratios and relations
## only — every number is read off the arranged fixture.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SUNDER := preload("res://effects/status/sunder.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]


func before_each() -> void:
	_h = H.new()
	_graph = _h.make_graph([[0, 1], [1, 2]], self)
	var e := _h.make_entity(_graph, "Red", Color.RED)
	_h.assign_owner(_graph, e, [0, 1, 2])
	_n = _graph.get_skill_nodes()


func _lctx(node: SkillNode, hop: int, extras: Array[PayloadState] = []) -> LandingContext:
	var c := PropagationContext.new()
	c.graph = _graph
	c.world = CombatWorld.shadow()
	var p := CastSpell.new()
	p.current_node = node
	p.graph = _graph
	p.hop_index = hop
	p.extras = extras
	return LandingContext.for_test(p, node, c)


func _hop(min_hop: int, max_hop: int) -> HopIndexCondition:
	var c := HopIndexCondition.new()
	c.min_hop = min_hop
	c.max_hop = max_hop
	return c


func _crack(stacks_share: float, min_value: float = -INF) -> CarriedScalar:
	var r := StatusShareReseed.new()
	r.status_id = _SUNDER.id
	r.share = stacks_share
	var s := CarriedScalar.new()
	s.id = &"crack"
	s.reseed = r
	s.min_value = min_value
	return s


# ── HopIndexCondition ──────────────────────────────────────────────────────


func test_max_hop_zero_holds_at_the_seed_only() -> void:
	var c := _hop(0, 0)
	assert_true(c.evaluate(_lctx(_n[1], 0)), "the seed")
	assert_false(c.evaluate(_lctx(_n[1], 1)), "hop 1")
	assert_false(c.evaluate(_lctx(_n[1], 3)), "hop 3")


func test_min_hop_one_unbounded_holds_off_the_seed() -> void:
	var c := _hop(1, -1)
	assert_false(c.evaluate(_lctx(_n[1], 0)), "not the seed")
	assert_true(c.evaluate(_lctx(_n[1], 1)), "hop 1")
	assert_true(c.evaluate(_lctx(_n[1], 7)), "any hop beyond")


func test_a_window_holds_inside_it_only() -> void:
	var c := _hop(1, 2)
	assert_false(c.evaluate(_lctx(_n[1], 0)))
	assert_true(c.evaluate(_lctx(_n[1], 2)))
	assert_false(c.evaluate(_lctx(_n[1], 3)))


# ── StatusShareReseed on a CarriedScalar ───────────────────────────────────


func test_the_reseed_reads_the_landed_stacks_not_the_carried_value() -> void:
	var stacks := 6.0
	_n[1].get_combat().apply_status(_SUNDER, stacks)
	var reseed := _crack(0.5).reseed
	var lctx := _lctx(_n[1], 1)
	assert_almost_eq(reseed.reseed(999.0, lctx, null), 0.5 * stacks, 0.001,
			"share × what is there now; the incoming value is ignored")
	assert_almost_eq(reseed.reseed(0.0, _lctx(_n[2], 1), null), 0.0, 0.001,
			"a clean node carries nothing")


func test_more_stacks_on_the_node_carry_a_bigger_crack() -> void:
	_n[1].get_combat().apply_status(_SUNDER, 4.0)
	_n[2].get_combat().apply_status(_SUNDER, 10.0)
	var crack := _crack(0.5)
	var pick := PropagationPick.new()
	var parent := crack.seed(null)
	var thin := crack.mint(parent, pick, _lctx(_n[1], 0), 0) as CarriedScalar.State
	var thick := crack.mint(parent, pick, _lctx(_n[2], 0), 0) as CarriedScalar.State
	assert_gt(thick.value, thin.value, "the re-read follows the node's stacks")


func test_a_crack_thinner_than_min_value_is_terminal() -> void:
	_n[1].get_combat().apply_status(_SUNDER, 1.0)
	_n[2].get_combat().apply_status(_SUNDER, 4.0)
	var crack := _crack(0.5, 1.0)
	var parent := crack.seed(null)
	var pick := PropagationPick.new()
	assert_true(crack.mint(parent, pick, _lctx(_n[1], 0), 0).terminal, "one stack halves below 1: the walk ends")
	assert_false(crack.mint(parent, pick, _lctx(_n[2], 0), 0).terminal, "four stacks carry on")


# ── ApplyStatusEffect.power_from ───────────────────────────────────────────


func _emitted_power(effect: ApplyStatusEffect, lctx: HitLanding) -> float:
	var before := lctx.hits.size()
	effect.apply(lctx)
	assert_eq(lctx.hits.size(), before + 1, "one status emitted")
	return (lctx.hits[lctx.hits.size() - 1] as StatusInstance).power


func _state(id: StringName, value: float) -> CarriedScalar.State:
	var tmpl := CarriedScalar.new()
	tmpl.id = id
	var st := CarriedScalar.State.new()
	st.template = tmpl
	st.value = value
	return st


func test_power_from_takes_the_carried_value() -> void:
	var fx := ApplyStatusEffect.new()
	fx.def = _SUNDER
	fx.power = 1.0
	fx.power_from = &"crack"
	var carried := 7.0
	var lctx := _lctx(_n[1], 1, [_state(&"crack", carried)] as Array[PayloadState])
	assert_almost_eq(_emitted_power(fx, lctx), carried, 0.001, "the carried value, not the authored power")


func test_power_from_falls_back_to_power_without_the_extension() -> void:
	var fx := ApplyStatusEffect.new()
	fx.def = _SUNDER
	fx.power = 3.0
	fx.power_from = &"crack"
	var lctx := _lctx(_n[1], 1, [_state(&"other", 9.0)] as Array[PayloadState])
	assert_almost_eq(_emitted_power(fx, lctx), fx.power, 0.001, "no crack on the payload")


func test_empty_power_from_ignores_a_carried_scalar() -> void:
	var fx := ApplyStatusEffect.new()
	fx.def = _SUNDER
	fx.power = 3.0
	var lctx := _lctx(_n[1], 1, [_state(&"crack", 9.0)] as Array[PayloadState])
	assert_almost_eq(_emitted_power(fx, lctx), fx.power, 0.001, "today's behaviour")


# ── CarriedScalar.seed_from_load ───────────────────────────────────────────


func test_seed_from_load_starts_the_scalar_at_the_casts_load() -> void:
	var crack := _crack(0.5)
	crack.seed_from_load = _SUNDER.id
	var ctx := PropagationContext.new()
	var load := 7
	ctx.load = {_SUNDER.id: load} as Dictionary[StringName, int]
	assert_almost_eq((crack.seed(ctx) as CarriedScalar.State).value, float(load), 0.001, "the concept's load")
	crack.seed_from_load = &""
	assert_almost_eq((crack.seed(ctx) as CarriedScalar.State).value, crack.seed_value, 0.001, "empty: seed_value")


# ── The shipped def, end to end ────────────────────────────────────────────

const _FAULT_LINE_PATH := "res://attack/spell/defs/fault_line.tres"


## A built board: Blue owns 0 (the caster's node); Red owns every index in
## [param red]; [param armor] arranges node armor by index.
class _Board:
	var graph: Graph
	var n: Array[SkillNode]
	var blue: Entity
	var red: Entity


func _board(adjacency: Array, red: Array, armor: Dictionary) -> _Board:
	var b := _Board.new()
	b.graph = _h.make_graph(adjacency, self)
	b.blue = _h.make_entity(b.graph, "Blue", Color.BLUE)
	b.red = _h.make_entity(b.graph, "Red", Color.RED)
	_h.give_big_hp(b.red)
	_h.assign_owner(b.graph, b.red, red)
	_h.assign_owner(b.graph, b.blue, [0])
	b.blue.stat_board.get_stat(&"crit_multiplier").base_value = 1.0
	b.n = b.graph.get_skill_nodes()
	for i in armor:
		var m := StatModifier.new()
		m.stat_id = &"armor"
		m.operation = StatModifier.Operation.ADD_BASE
		m.value = armor[i] - float(b.n[i].get_local_value(&"armor"))
		b.n[i].add_local_modifier(m)
	return b


## Blue 0 — Red 1 — 2 — … — [param length]; armor rising along the chain so
## only the struck node 1 is a weak point, and thick enough that no landing
## strips a node to zero.
func _chain(length: int) -> _Board:
	var adj := [[0, 1]]
	var red := []
	var armor := {0: 1000.0}
	for i in range(1, length + 1):
		red.append(i)
		armor[i] = 200.0 + 10.0 * i
		if i < length:
			adj.append([i, i + 1])
	return _board(adj, red, armor)


func _fault_line(max_hops: float = -1.0) -> SpellDef:
	var spell := load(_FAULT_LINE_PATH) as SpellDef
	if max_hops >= 0.0:
		spell = spell.duplicate()
		spell.propagation = spell.propagation.duplicate()
		spell.propagation.max_hops = max_hops
	return spell


## Landed Sunder by node index (absent = no landing).
func _landed(b: _Board, spell: SpellDef, points: int = 0) -> Dictionary:
	var inf := Infusion.for_cast(spell, {_SUNDER.id: points}) if points > 0 else null
	var outcome := SpellResolver.resolve(spell, b.n[1], b.n[0], b.blue, b.graph, null, inf)
	var out := {}
	for hit in outcome.hits:
		if hit is StatusInstance and hit.def == _SUNDER:
			var i := b.n.find(hit.target)
			out[i] = out.get(i, 0.0) + hit.amount
	return out


func _load(spell: SpellDef, points: int = 0) -> int:
	return Infusion.for_cast(spell, {_SUNDER.id: points}).load_of(spell)[_SUNDER.id]


func _share(spell: SpellDef) -> float:
	return (spell.propagation.extensions[0].reseed as StatusShareReseed).share


func test_def_shape() -> void:
	var spell := _fault_line()
	assert_eq(spell.on_hit_effects.filter(func(e): return e is ApplyStatusEffect).size(), 0,
			"no authored status effect: the crack rides the intake rider (ADR 0047)")
	assert_null(spell.rider_when, "the rider lands at every hop")
	assert_eq(spell.intakes[0].identity, _SUNDER.identity, "a native Sunder intake")
	assert_eq(spell.intakes[0].power_from, spell.propagation.extensions[0].id, "the rider reads the crack")
	var crit := spell.crit_conditions[0] as LocalExtremumCondition
	assert_not_null(crit, "the weak-point crit")
	assert_eq(crit.mode, LocalExtremumCondition.Mode.MIN, "where armor is lowest")
	assert_eq((crit.ranker as StatRanker).stat_id, &"armor")


func test_clean_chain_lands_share_of_the_previous_landing_per_hop() -> void:
	var spell := _fault_line()
	var hops := int(spell.propagation.max_hops)
	var b := _chain(hops + 3)
	var got := _landed(b, spell)
	assert_eq(got.get(1, 0.0), float(_load(spell)), "hop 0 lands exactly the load")
	for k in range(1, hops + 1):
		assert_eq(got.get(k + 1, 0.0), float(StatusDef.round_half_up(_share(spell) * got.get(k, 0.0))),
				"hop %d lands share × hop %d" % [k, k - 1])
	assert_false(got.has(hops + 2), "the walk ends at max_hops")


func test_a_bigger_load_lands_more_at_every_hop() -> void:
	var spell := _fault_line()
	var hops := int(spell.propagation.max_hops)
	var b := _chain(hops + 2)
	var thin := _landed(b, spell)
	var b2 := _chain(hops + 2)
	var points := 200
	assert_gt(_load(spell, points), _load(spell), "fixture: the infusion raises the load")
	var thick := _landed(b2, spell, points)
	for k in range(1, hops + 2):
		assert_gt(thick.get(k, 0.0), thin.get(k, 0.0), "node %d" % k)


func test_stacks_per_hit_fold_into_every_crack_landing() -> void:
	var spell := _fault_line()
	var hops := int(spell.propagation.max_hops)
	var b := _chain(hops + 2)
	var p := 2.0
	b.blue.stat_board.get_stat(_SUNDER.stacks_stat_id()).base_value = p
	var got := _landed(b, spell)
	for k in range(1, hops + 1):
		assert_eq(got.get(k + 1, 0.0), float(StatusDef.round_half_up(_share(spell) * got.get(k, 0.0))) + p,
				"hop %d: share × previous, plus the caster's stacks per hit" % k)


func test_a_thin_crack_ends_the_walk_before_a_long_max_hops() -> void:
	var spell := _fault_line(20.0)
	var b := _chain(20)
	var got := _landed(b, spell)
	assert_lt(got.size(), 20, "the crack runs out before the chain does")
	assert_gt(got.size(), int(_fault_line().propagation.max_hops) + 1, "fixture: longer than the shipped max_hops")


func test_pre_sundered_ground_carries_the_crack_further() -> void:
	var spell := _fault_line(20.0)
	var clean := _landed(_chain(20), spell)
	var b := _chain(20)
	for i in range(2, 21):
		b.n[i].get_combat().apply_status(_SUNDER, 4.0)
	var cracked := _landed(b, spell)
	assert_gt(cracked.size(), clean.size(), "pre-sundered nodes keep the crack alive longer")


func test_a_crit_at_hop_zero_sends_double_down_the_crack() -> void:
	var spell := _fault_line()
	var b := _chain(int(spell.propagation.max_hops) + 2)
	var mult := 2.0
	b.blue.stat_board.get_stat(&"crit_multiplier").base_value = mult
	var got := _landed(b, spell)
	assert_eq(got.get(1, 0.0), mult * _load(spell), "the struck node is the weak point: critted")
	assert_eq(got.get(2, 0.0), float(StatusDef.round_half_up(_share(spell) * got.get(1, 0.0))),
			"hop 1 re-reads the critted amount")


func test_two_fronts_meeting_carry_max_not_sum() -> void:
	# 1 forks into 2 and 3 (equal armor), both reach 4. Node 2 carries 6
	# extra stacks, so its crack is the bigger one.
	var spell := _fault_line()
	var b := _board([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [1, 2, 3, 4],
			{0: 1000.0, 1: 100.0, 2: 300.0, 3: 300.0, 4: 300.0})
	b.n[2].get_combat().apply_status(_SUNDER, 6.0)
	var got := _landed(b, spell)
	var share := _share(spell)
	var from2: float = share * (got[2] + 6.0)
	var from3: float = share * got[3]
	assert_gt(from2, from3, "fixture: the fronts differ")
	assert_eq(got.get(4, 0.0), float(StatusDef.round_half_up(maxf(from2, from3))), "MAX of the two cracks")


func test_the_crack_skips_unarmored_and_neutral_and_keeps_two_armor_places() -> void:
	# Seed 1's neighbours: 2/3 at the top armor, 4 second, 5 third, 6 armor 0,
	# 7 neutral (unowned) with the most armor of all.
	var spell := _fault_line()
	var b := _board([[0, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [1, 7]], [1, 2, 3, 4, 5, 6],
			{0: 1000.0, 1: 100.0, 2: 300.0, 3: 300.0, 4: 250.0, 5: 200.0, 6: 0.0, 7: 900.0})
	var got := _landed(b, spell)
	for i in [2, 3, 4]:
		assert_true(got.has(i), "node %d: places 1|2" % i)
	assert_false(got.has(5), "place 3 dropped")
	assert_false(got.has(6), "armor 0 skipped")
	assert_false(got.has(7), "neutral skipped")
