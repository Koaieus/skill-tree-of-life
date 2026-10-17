extends GutTest

## Explosive charges on blade contacts: one contact, two sides. The striker's
## side (load + r·shared) blasts the board around the struck node; the node's
## side (present + r·shared) reaches the blade pieces around it — plain ones
## pop, charged ones shrug. Both spend max(1, shared) if they hold any. Gate-level: each test hands a
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


func _arm(gate: BladePopResolver.LiveGate, _state: BladeState, contact: Array, riders: Array = []) -> Array[HitInstance]:
	var hits: Array[HitInstance] = []
	gate.arm_blasts(contact[0], contact[1], hits, CombatWorld.live(), riders)
	return hits


func _shrapnel_on(hits: Array[HitInstance], node: SkillNode) -> float:
	var total := 0.0
	for h in hits:
		var token := h.paired as BladePopResolver.BlastToken
		if h is PairedDamageInstance and h.target == node and token != null \
				and token.blast_kind == BladePopResolver.LiveGate.BLAST:
			total += h.amount
	return total


func _share() -> float:
	return BladePopResolver.LiveGate.new(null, null).warhead_reach


## Scale the struck target so a [param power] blast's reach is [param px].
func _size_target(power: int, px: float) -> void:
	_f.target.base_radius *= px / (_share() * _spread().radius_for(_f.target.radius, power))


func _only_contact(gate: BladePopResolver.LiveGate) -> BladePopResolver.Contact:
	assert_eq(gate.result.contacts.size(), 1, "one contact row")
	return gate.result.contacts[0] if gate.result.contacts.size() == 1 else BladePopResolver.Contact.new(0.0, null)


func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


# ── 1. the striker's side ────────────────────────────────────────────────────

func test_blast_reaches_a_hostile_in_the_striker_sides_reach_and_spends_one_life() -> void:
	_size_target(2, 200.0)
	var piece := _f.leaves[0]
	var state := _blade([Vector2(430, 0)], [2])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()), "a piece that keeps a life hits as usual")
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.BLAST, "the contact set the blast off")
	assert_eq(state.vertex_charges[1], 1, "one life spent")
	assert_false(gate.result.dead_at.has(1), "the piece lives")
	assert_gt(_shrapnel_on(hits, _f.cluster[0]), 0.0, "the blast reaches a hostile in range")
	assert_eq(_shrapnel_on(hits, _f.cluster[1]), 0.0, "and nothing past its reach")
	for h in hits:
		assert_ne(h.target.owned_by, _f.attacker, "the blast never hits the swinger's own nodes")
		assert_true(h.rider_gated(h.target.get_combat(), CombatWorld.live()) == false or h.target == _f.target,
				"the armed blast lands once the gate fired it")
	var spends := gate.take_spends()
	assert_eq(spends.size(), 1, "one spend recorded")
	assert_eq([spends[0].node, spends[0].count], [piece, 1], "off the piece's own node")


func test_blast_on_its_last_life_kills_the_piece_mid_swing() -> void:
	var state := _blade([Vector2(430, 0), Vector2(430, 40)], [1, 0])
	state.edges.append(Vector2i(1, 2))
	state.edges.remove_at(1)  # piece 2 hangs off piece 1 only
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece exploded")
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.BLAST, "and still blasted")
	assert_eq(gate.result.dead_at, {1: 0.5}, "it dies at the contact")
	assert_eq(gate.result.severances.size(), 1, "its edges go with it")
	assert_eq(Array(gate.result.severances[0].vertices), [2], "what hung off it comes away")


# ── 2. the node's side ───────────────────────────────────────────────────────

func test_barrel_pops_plain_pieces_in_reach_and_leaves_a_charged_one() -> void:
	_charge(_f.target, 2.0)
	var r := _share() * _spread().radius_for(_f.target.radius, 2)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 0.5 * r), t + Vector2(0, -0.5 * r), t + Vector2(0, 1.5 * r)],
			[0, 1, 0, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c)
	assert_eq(hits.size(), 0, "an uncharged piece arms no board blast")
	assert_false(gate.admit(c[0], CombatWorld.live()), "the contact piece pops")
	assert_eq(gate.blast_of(c[0]), &"", "no board blast: the node's side reaches blade pieces only")
	assert_eq(_sorted(gate.result.dead_at.keys()), [1, 3], "the contact and the plain piece in reach pop")
	assert_eq(state.vertex_charges[2], 1, "the charged piece in reach is armed, not fragile: untouched")
	assert_false(gate.result.dead_at.has(2), "and lives")
	assert_false(gate.result.dead_at.has(4), "a piece out of reach is untouched")
	assert_eq(gate.node_charges(_f.target.get_combat()), 1, "the node spends 1")
	assert_eq(_f.target.get_combat().get_status_power(&"explosive"), 2.0, "no live write yet")
	var cures := _land_spends(gate)
	assert_eq(cures.size(), 1, "only the node's spend")
	assert_eq(_f.target.get_combat().get_status_power(&"explosive"), 1.0, "the node ends with 1")
	assert_eq(gate.node_charges(_f.target.get_combat()), 1, "and the gate's read agrees once landed")


## The gate's recorded spends as [SwingResolve] turns them into hits, landed.
func _land_spends(gate: BladePopResolver.LiveGate) -> Array[HitInstance]:
	var ctx := SwingContext.new()
	ctx.attacker = _f.attacker
	var run := SwingResolve.new(ctx)
	var hits: Array[HitInstance] = []
	run._append_spends(hits, gate)
	for h in hits:
		assert_true(h is CureInstance, "a spend is a cleanse on the record")
		h.land_on(h.target.get_combat(), CombatWorld.live())
	return hits


# ── 3. both sides ────────────────────────────────────────────────────────────

func test_both_charged_larger_piece_lives_on_with_the_difference() -> void:
	_charge(_f.target, 1.0)
	var state := _blade([Vector2(430, 0)], [3])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()), "the piece lives on")
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.BLAST, "one board blast")
	assert_eq(state.vertex_charges[1], 2, "N - M left on the piece")
	assert_eq(gate.node_charges(_f.target.get_combat()), 0, "the node is spent")


func test_both_charged_larger_node_pops_the_piece_and_keeps_the_difference() -> void:
	_charge(_f.target, 3.0)
	var state := _blade([Vector2(430, 0)], [1])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece pops")
	assert_true(gate.result.dead_at.has(1), "dead mid-swing")
	assert_eq(gate.node_charges(_f.target.get_combat()), 2, "M - N left on the node")


func test_board_reach_grows_with_the_striker_side_and_piece_reach_with_the_node_side() -> void:
	var res := _spread().resonance
	var gap := _f.target.global_position.distance_to(_f.cluster[0].global_position) - _f.cluster[0].radius
	_size_target(1 + res, 1.2 * gap)
	assert_lt(_share() * _spread().radius_for(_f.target.radius, 1), gap,
			"fixture: a lone charge's reach falls short of cluster[0]")
	var amounts: Array[float] = []
	var reaches: Array[float] = []
	for m in [0, 1]:  # the target starts clean; charged once, before the second
		if m > 0:
			_charge(_f.target, 1.0)
		var state := _blade([Vector2(430, 0)], [1])
		var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
		var c := _contact(gate, 1, _f.target)
		amounts.append(_shrapnel_on(_arm(gate, state, c), _f.cluster[0]))
		gate.admit(c[0], CombatWorld.live())
		reaches.append(_only_contact(gate).piece_reach)
	assert_eq(amounts[0], 0.0, "1 on 0: striker side 1 falls short")
	assert_gt(amounts[1], 0.0, "1 on 1: striker side 1 + r reaches cluster[0]")
	assert_eq(reaches[0], 0.0, "1 on 0: no node side")
	assert_almost_eq(reaches[1], _share() * _spread().radius_for(_f.target.radius, 1 + res), 0.001,
			"1 on 1: node side 1 + r")


# ── 4. a blade blast chains like any blast ──────────────────────────────────

func test_blade_blast_over_a_charged_node_sets_it_off_once() -> void:
	_charge(_f.cluster[0], 2.0)
	_size_target(2, 200.0)
	var poison := ApplyStatusEffect.new()
	poison.def = preload("res://effects/status/poison.tres")
	var riders: Array = [poison]  # a blade's riders as the swing hands them: unarmed
	var state := _blade([Vector2(430, 0)], [2])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c, riders)
	assert_gt(_shrapnel_on(hits, _f.cluster[0]), 0.0, "the blast covers the charged node")
	var on_cluster := 0
	for h in hits:
		if h is CureInstance:
			assert_ne(h.target, _f.target, "the struck node's spend is the gate's, never the chain's")
			if h.target == _f.cluster[0]:
				on_cluster += 1
	assert_eq(on_cluster, 1, "the charged node goes off once per contact")


# ── 5. the owner's worked numbers ───────────────────────────────────────────

func test_100_on_0_reaches_the_board_and_no_piece() -> void:
	var t := _f.target.global_position
	var state := _blade([Vector2(430, 0), t + Vector2(0, 5)], [100, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	var hits := _arm(gate, state, c)
	var mark: BlastMark = hits[0].blast_mark if not hits.is_empty() else null
	assert_almost_eq(mark.reach if mark != null else -1.0,
			_share() * _spread().radius_for(_f.target.radius, 100), 0.001, "the warhead's mark: the striker side's reach")
	assert_eq(mark.power if mark != null else -1, 100, "the warhead's mark: the striker side's power")
	assert_true(gate.admit(c[0], CombatWorld.live()))
	assert_eq(gate.blast_of(c[0]), BladePopResolver.LiveGate.BLAST, "the board side goes off")
	assert_eq(state.vertex_charges[1], 99, "the piece spends 1")
	assert_false(gate.result.dead_at.has(2), "a plain piece on the node is untouched")
	var row := _only_contact(gate)
	assert_eq(row.piece_reach, 0.0, "no node side")
	assert_eq(row.striker_power, 100)
	assert_eq(row.node_power, 0)
	assert_eq(row.verdicts, {1: BladePopResolver.Contact.Verdict.SPENT}, "only the striker's verdict")


func test_0_on_100_pops_every_plain_piece_in_reach_and_spends_one() -> void:
	_charge(_f.target, 100.0)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 30), t + Vector2(30, 0)], [0, 0, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_eq(_arm(gate, state, c).size(), 0, "no striker side, no board blast")
	assert_false(gate.admit(c[0], CombatWorld.live()))
	assert_eq(gate.blast_of(c[0]), &"")
	assert_eq(_sorted(gate.result.dead_at.keys()), [1, 2, 3], "every plain piece in reach pops")
	assert_eq(gate.node_charges(_f.target.get_combat()), 99, "the node spends 1")


func test_100_on_1_sizes_each_side_and_records_the_verdicts() -> void:
	_charge(_f.target, 1.0)
	var res := _spread().resonance
	var reach := _share() * _spread().radius_for(_f.target.radius, 1 + res)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 0.5 * reach), t + Vector2(0, -0.5 * reach),
			t + Vector2(0, 1.5 * reach)], [100, 0, 2, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()), "the striker keeps 99 lives")
	assert_eq(state.vertex_charges[1], 99, "the piece spends 1")
	assert_eq(gate.node_charges(_f.target.get_combat()), 0, "the node spends 1")
	var row := _only_contact(gate)
	assert_almost_eq(row.piece_reach, reach, 0.001, "the piece reach is radius_for(r, 1 + r·1)")
	assert_eq(row.striker_power, 100 + res, "the board side is 100 + r·1")
	assert_eq(row.node_power, 1 + res)
	assert_eq(row.t, 0.5)
	assert_eq(row.struck, _f.target)
	assert_eq(row.centre, t, "the bomb is the node")
	var V := BladePopResolver.Contact.Verdict
	assert_eq(row.verdicts, {1: V.SPENT, 2: V.POPPED, 3: V.SHRUGGED}, "piece 4 is out of reach and absent")
	assert_eq(state.vertex_charges[3], 2, "a shrugged piece keeps its charges")
	assert_false(gate.result.dead_at.has(3), "and lives")
	for spend in gate.take_spends():
		assert_ne(spend.node, state.vertex_node[3], "and spends nothing")


## Two uncharged pieces and one charged piece in the node side's reach; the
## shielded ones (a `deflection` source) shrug — the uncharged one spends
## nothing, the charged one spends exactly as an unshielded charged piece.
func test_a_shielded_piece_shrugs_the_node_side_spending_nothing() -> void:
	_charge(_f.target, 1.0)
	var res := _spread().resonance
	var reach := _share() * _spread().radius_for(_f.target.radius, 1 + res)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 0.5 * reach), t + Vector2(0, -0.5 * reach)],
			[100, 0, 0])
	state.vertex_shielded[2] = 1
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()))
	var V := BladePopResolver.Contact.Verdict
	assert_eq(_only_contact(gate).verdicts, {1: V.SPENT, 2: V.SHRUGGED, 3: V.POPPED},
			"the shielded piece shrugs; the same piece unshielded pops")
	assert_false(gate.result.dead_at.has(2), "the shielded piece lives")
	assert_true(gate.result.dead_at.has(3), "the plain piece dies")
	for spend in gate.take_spends():
		assert_ne(spend.node, state.vertex_node[2], "a shielded piece spends nothing")


func test_a_charged_shielded_piece_spends_as_a_charged_one() -> void:
	_charge(_f.target, 1.0)
	var res := _spread().resonance
	var reach := _share() * _spread().radius_for(_f.target.radius, 1 + res)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 0.5 * reach)], [100, 2])
	state.vertex_shielded[1] = 1
	state.vertex_shielded[2] = 1
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_true(gate.admit(c[0], CombatWorld.live()))
	assert_eq(state.vertex_charges[1], 99, "the contact's own piece spends 1, shield or not")
	assert_eq(state.vertex_charges[2], 2, "a shrugged charged piece keeps its charges")
	var V := BladePopResolver.Contact.Verdict
	assert_eq(_only_contact(gate).verdicts, {1: V.SPENT, 2: V.SHRUGGED})
	var spent := gate.take_spends().filter(func(s): return s.node == state.vertex_node[1])
	assert_eq(spent.size(), 1, "one spend on the contact's piece, no double effect")


func test_fill_shields_a_vertex_whose_source_grants_deflection() -> void:
	var bunker := (load("res://skill_node/addons/defs/bunker_addon.tscn") as PackedScene).instantiate()
	_f.leaves[0].add_child(bunker)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0], _f.leaves[1]]
	var state := _blade([Vector2(400, 0), Vector2(450, 150)], [0, 0])
	BladeVertexFill.new().fill(state, nodes)
	assert_eq(state.vertex_shielded[1], 1, "the bunker vertex is shielded")
	assert_eq(state.vertex_shielded[2], 0, "a plain vertex is not")


func test_3_on_5_both_spend_3_and_the_piece_dies() -> void:
	_charge(_f.target, 5.0)
	var res := _spread().resonance
	var state := _blade([Vector2(430, 0)], [3])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_arm(gate, state, c)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece dies mid swing")
	assert_true(gate.result.dead_at.has(1))
	assert_eq(state.vertex_charges[1], 0, "the piece spends 3")
	assert_eq(gate.node_charges(_f.target.get_combat()), 2, "the node spends 3")
	var row := _only_contact(gate)
	assert_eq(row.striker_power, 3 + 3 * res, "board side 3 + 3r")
	assert_eq(row.node_power, 5 + 3 * res, "piece side 5 + 3r")
	assert_eq(row.verdicts[1], BladePopResolver.Contact.Verdict.POPPED, "the striker ends at 0")
