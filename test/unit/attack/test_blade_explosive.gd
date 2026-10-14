extends GutTest

## Explosive charges on blade contacts (#1595): the warhead, the barrel pop,
## the min(N,M) exchange, charges as lives. Gate-level: each test hands a
## hand-built blade's contact to [BladePopResolver.LiveGate], arming the
## contact's blasts first exactly as [SwingResolve] does. Radii are asserted
## as ratios of [method ExplosiveSpread.radius_for], never literals.
##
## Board: VolleyBoardFixture — target (450,0) hostile; cluster[0] (600,0) and
## cluster[1] (700,100) hostile; the attacker owns the hub and the leaves.

var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _spread() -> ExplosiveSpread:
	return BladePopResolver.LiveGate.explosive_spread()


func _charge(node: SkillNode, n: float) -> void:
	node.get_combat().apply_status(BladePopResolver.LiveGate.explosive_def(), n)


## A star blade: pivot 0 on the hub, pieces 1.. at [param at], each on its
## own attacker node, charged per [param charges].
func _blade(at: Array[Vector2], charges: Array[int]) -> BladeState:
	var positions: Array[Vector2] = [Vector2(-400, 0)]
	var radii: Array[float] = [16.0]
	var edges: Array[Vector2i] = []
	for i in at.size():
		positions.append(at[i])
		radii.append(16.0)
		edges.append(Vector2i(0, i + 1))
	var s := BladeState.build(positions, 0, edges, radii)
	s.vertex_node[0] = _f.hub
	for i in at.size():
		s.vertex_node[i + 1] = _f.leaves[mini(i, _f.leaves.size() - 1)]
		s.vertex_charges[i + 1] = charges[i]
	return s


func _contact(gate: BladePopResolver.LiveGate, idx: int, target: SkillNode) -> Array:
	var ev := BladeHitEvent.new(0.5, idx, -1, target)
	var di := BladeDamageInstance.new(ev, gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = target
	di.attacker = _f.attacker
	return [ev, di]


func _arm(gate: BladePopResolver.LiveGate, state: BladeState, contact: Array, riders: Array = []) -> Array[HitInstance]:
	var hits: Array[HitInstance] = []
	gate.arm_blasts(contact[0], contact[1], hits, CombatWorld.live(), riders)
	return hits


func _shrapnel_on(hits: Array[HitInstance], node: SkillNode, kind: StringName) -> float:
	var total := 0.0
	for h in hits:
		var token := h.paired as BladePopResolver.BlastToken
		if h is PairedDamageInstance and h.target == node and token != null and token.blast_kind == kind:
			total += h.amount
	return total


# ── 1. warhead ───────────────────────────────────────────────────────────────

func test_warhead_blasts_hostiles_in_reach_and_spends_one_life() -> void:
	var piece := _f.leaves[0]
	var reach := BladePopResolver.LiveGate.new(null, null).warhead_reach * _spread().radius_for(piece.radius, 2)
	piece.base_radius *= 200.0 / reach
	reach = BladePopResolver.LiveGate.new(null, null).warhead_reach * _spread().radius_for(piece.radius, 2)
	assert_between(reach, 151.0, 268.0, "fixture: the warhead reaches cluster[0] only")
	var state := _blade([Vector2(430, 0)], [2])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()), "a piece that keeps a life hits as usual")
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.WARHEAD, "the contact set the warhead off")
	assert_eq(state.vertex_charges[1], 1, "one life spent")
	assert_false(gate.result.dead_at.has(1), "the piece lives")
	assert_gt(_shrapnel_on(hits, _f.cluster[0], &"warhead"), 0.0, "the blast reaches a hostile in range")
	assert_eq(_shrapnel_on(hits, _f.cluster[1], &"warhead"), 0.0, "and nothing past its reach")
	for h in hits:
		assert_ne(h.target.owned_by, _f.attacker, "the blast never hits the swinger's own nodes")
		assert_true(h.rider_gated(h.target.get_combat()) == false or h.target == _f.target,
				"the armed blast lands once the gate fired it")
	var spends := gate.take_spends()
	assert_eq(spends.size(), 1, "one spend recorded")
	assert_eq([spends[0].node, spends[0].count], [piece, 1], "off the piece's own node")


func test_warhead_on_its_last_life_kills_the_piece_mid_swing() -> void:
	var state := _blade([Vector2(430, 0), Vector2(430, 40)], [1, 0])
	state.edges.append(Vector2i(1, 2))
	state.edges.remove_at(1)  # piece 2 hangs off piece 1 only
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece exploded")
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.WARHEAD, "and still blasted")
	assert_eq(gate.result.dead_at, {1: 0.5}, "it dies at the contact")
	assert_eq(gate.result.severances.size(), 1, "its edges go with it")
	assert_eq(Array(gate.result.severances[0].vertices), [2], "what hung off it comes away")


# ── 2. barrel ────────────────────────────────────────────────────────────────

func test_barrel_pops_blade_pieces_in_reach_and_a_charged_one_spends_a_life() -> void:
	_charge(_f.target, 2.0)
	var r := _spread().radius_for(_f.target.radius, 2)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 0.5 * r), t + Vector2(0, -0.5 * r), t + Vector2(0, 1.5 * r)],
			[0, 1, 0, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c)
	assert_eq(hits.size(), 0, "an uncharged piece arms no board blast")
	assert_false(gate.admit(c[0], CombatWorld.live()), "the contact piece pops")
	assert_eq(gate.blast_of(c[0]), &"", "no board blast: the barrel touches blade pieces only")
	assert_eq(_sorted(gate.result.dead_at.keys()), [1, 3], "the contact and the uncharged piece in reach pop")
	assert_eq(state.vertex_charges[2], 0, "the charged piece in reach spent its life")
	assert_false(gate.result.dead_at.has(2), "and lives")
	assert_false(gate.result.dead_at.has(4), "a piece out of reach is untouched")
	assert_eq(gate.node_charges(_f.target.get_combat()), 1, "the barrel ends with 1")


# ── 3. exchange ──────────────────────────────────────────────────────────────

func test_exchange_larger_piece_lives_on_with_the_difference() -> void:
	_charge(_f.target, 1.0)
	var state := _blade([Vector2(430, 0)], [3])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()), "the piece lives on")
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.EXCHANGE, "one exchange blast")
	assert_eq(state.vertex_charges[1], 2, "N - M left on the piece")
	assert_eq(gate.node_charges(_f.target.get_combat()), 0, "the node is spent")


func test_exchange_larger_node_pops_the_piece_and_keeps_the_difference() -> void:
	_charge(_f.target, 3.0)
	var state := _blade([Vector2(430, 0)], [1])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece pops")
	assert_true(gate.result.dead_at.has(1), "dead mid-swing")
	assert_eq(gate.node_charges(_f.target.get_combat()), 2, "M - N left on the node")


func test_exchange_shrapnel_scales_with_min_n_m() -> void:
	_charge(_f.target, 2.0)
	assert_between(_spread().radius_for(_f.target.radius, 2), 151.0, 268.0,
			"fixture: 2 charges on the target reach cluster[0] only")
	var amounts: Array[float] = []
	for n in [1, 2]:
		var state := _blade([Vector2(430, 0)], [n])
		var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
		var c := _contact(gate, 1, _f.target)
		amounts.append(_shrapnel_on(_arm(gate, state, c), _f.cluster[0], &"exchange"))
	assert_gt(amounts[0], 0.0, "the exchange blast reaches cluster[0]")
	assert_almost_eq(amounts[1] / amounts[0], 2.0, 0.0001, "min 2 deals twice min 1's shrapnel")


# ── 4. blade blasts never set off board charges ─────────────────────────────

func test_warhead_blast_over_a_charged_node_does_not_set_it_off() -> void:
	_charge(_f.cluster[0], 2.0)
	var piece := _f.leaves[0]
	piece.base_radius *= 400.0 / _spread().radius_for(piece.radius, 2)
	var poison := ApplyStatusEffect.new()
	poison.def = preload("res://effects/status/poison.tres")
	var riders: Array = DetonateEffect.arm([poison] as Array[OnHitEffect])
	var state := _blade([Vector2(430, 0)], [2])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c, riders)
	assert_gt(_shrapnel_on(hits, _f.cluster[0], &"warhead"), 0.0, "the blast covers the charged node")
	for h in hits:
		assert_false(h is CureInstance, "nothing spends a board charge")
	gate.admit(c[0], CombatWorld.live())
	for spend in gate.take_spends():
		assert_ne(spend.node, _f.cluster[0], "the charged node keeps its charges")


func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out
