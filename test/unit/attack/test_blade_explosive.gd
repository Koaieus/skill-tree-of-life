extends GutTest

## Explosive charges on blade contacts: the piece's side alone. A charged
## piece spends max(1, min(N, M)) of its own charges on a contact and pops when
## it ends at 0; it arms no board blast, and no node's side reaches the blade
## pieces. The gate never reads-and-spends the struck node: its charges are
## the gather's to spend. Gate-level: each test hands a hand-built blade's
## contact to [BladePopResolver.LiveGate], stamping the head's load first
## exactly as [SwingResolve] does.
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


## The head's load stamped as [SwingResolve] does before it lands.
func _stamp(gate: BladePopResolver.LiveGate, contact: Array) -> void:
	gate.stamp_load(contact[0], contact[1])


func _contact(gate: BladePopResolver.LiveGate, idx: int, target: SkillNode) -> Array:
	var ev := BladeHitEvent.new(0.5, idx, -1, target)
	var di := BladeDamageInstance.new(ev, gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = target
	di.attacker = _f.attacker
	return [ev, di]














func _only_contact(gate: BladePopResolver.LiveGate) -> BladePopResolver.Contact:
	assert_eq(gate.result.contacts.size(), 1, "one contact row")
	return gate.result.contacts[0] if gate.result.contacts.size() == 1 else BladePopResolver.Contact.new(0.0, null)




# ── 1. the piece's side ──────────────────────────────────────────────────────

func test_a_charged_piece_spends_one_life_on_a_clean_node() -> void:
	var state := _blade([Vector2(430, 0)], [2])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_true(gate.admit(c[0], CombatWorld.live()), "a piece that keeps a life hits as usual")
	assert_eq(state.vertex_charges[1], 1, "one life spent")
	assert_false(gate.result.dead_at.has(1), "the piece lives")


func test_a_charged_piece_on_its_last_life_dies_mid_swing() -> void:
	var state := _blade([Vector2(430, 0), Vector2(430, 40)], [1, 0])
	state.edges.append(Vector2i(1, 2))
	state.edges.remove_at(1)  # piece 2 hangs off piece 1 only
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece exploded")
	assert_eq(gate.result.dead_at, {1: 0.5}, "it dies at the contact")
	assert_eq(gate.result.severances.size(), 1, "its edges go with it")
	assert_eq(Array(gate.result.severances[0].vertices), [2], "what hung off it comes away")


# ── 2. no node's side, and the node is never the gate's to spend ─────────────

func test_an_uncharged_piece_on_a_charged_node_lands_and_pops_nothing() -> void:
	_charge(_f.target, 2.0)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 20), t + Vector2(0, -20)], [0, 1, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_true(gate.admit(c[0], CombatWorld.live()), "the contact lands its one hit")
	assert_eq(gate.result.dead_at, {}, "no piece pops: the node reaches no blade piece")
	assert_true(gate.result.contacts.is_empty(), "an uncharged piece makes no contact row")
	assert_eq(gate.node_charges(_f.target.get_combat()), 2, "the gate spends nothing off the node")
	assert_eq(_f.target.get_combat().get_status_power(&"explosive"), 2.0, "and writes nothing")


func test_both_charged_larger_piece_lives_on_with_the_difference() -> void:
	_charge(_f.target, 1.0)
	var state := _blade([Vector2(430, 0)], [3])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_true(gate.admit(c[0], CombatWorld.live()), "the piece lives on")
	assert_eq(state.vertex_charges[1], 2, "N - M left on the piece")
	assert_eq(gate.node_charges(_f.target.get_combat()), 1, "the node's charge is the gather's, untouched here")


func test_both_charged_larger_node_pops_the_piece() -> void:
	_charge(_f.target, 3.0)
	var state := _blade([Vector2(430, 0)], [1])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece pops")
	assert_true(gate.result.dead_at.has(1), "dead mid-swing")
	assert_eq(gate.node_charges(_f.target.get_combat()), 3, "the node keeps all its charges")


# ── 3. the owner's worked numbers, the piece's side ──────────────────────────

func test_100_on_0_spends_one_and_leaves_a_plain_piece_be() -> void:
	var t := _f.target.global_position
	var state := _blade([Vector2(430, 0), t + Vector2(0, 5)], [100, 0])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	_stamp(gate, c)
	assert_eq(c[1].hit_load, 100, "the head carries the piece's charges as its load")
	assert_true(gate.admit(c[0], CombatWorld.live()))
	assert_eq(state.vertex_charges[1], 99, "the piece spends 1")
	assert_false(gate.result.dead_at.has(2), "a plain piece on the node is untouched")
	var row := _only_contact(gate)
	assert_eq(row.piece_reach, 0.0, "no node side")
	assert_eq(row.striker_power, 100)
	assert_eq(row.node_power, 0)
	assert_eq(row.verdicts, {1: BladePopResolver.Contact.Verdict.SPENT}, "only the striker's verdict")


func test_100_on_1_records_the_powers_and_only_the_strikers_verdict() -> void:
	_charge(_f.target, 1.0)
	var res := _spread().resonance
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 10), t + Vector2(0, -10)], [100, 0, 2])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_true(gate.admit(c[0], CombatWorld.live()), "the striker keeps 99 lives")
	assert_eq(state.vertex_charges[1], 99, "the piece spends 1")
	assert_eq(gate.node_charges(_f.target.get_combat()), 1, "the node is not the gate's to spend")
	var row := _only_contact(gate)
	assert_eq(row.piece_reach, 0.0, "no node side reaches the pieces")
	assert_eq(row.striker_power, 100 + res, "100 + r·1")
	assert_eq(row.node_power, 1 + res)
	assert_eq(row.t, 0.5)
	assert_eq(row.struck, _f.target)
	assert_eq(row.centre, t, "the bomb is the node")
	assert_eq(row.verdicts, {1: BladePopResolver.Contact.Verdict.SPENT}, "no other piece is considered")
	assert_eq(gate.result.dead_at, {}, "the plain piece beside it lives")
	assert_eq(state.vertex_charges[3], 2, "a charged piece beside it keeps its charges")


func test_a_charged_shielded_piece_spends_as_a_charged_one() -> void:
	_charge(_f.target, 1.0)
	var t := _f.target.global_position
	var state := _blade([t + Vector2(-10, 0), t + Vector2(0, 10)], [100, 2])
	state.vertex_shielded[1] = 1
	state.vertex_shielded[2] = 1
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_true(gate.admit(c[0], CombatWorld.live()))
	assert_eq(state.vertex_charges[1], 99, "the contact's own piece spends 1, shield or not")
	assert_eq(state.vertex_charges[2], 2, "a piece beside it keeps its charges")
	assert_eq(_only_contact(gate).verdicts, {1: BladePopResolver.Contact.Verdict.SPENT})


func test_fill_shields_a_vertex_whose_source_grants_deflection() -> void:
	var bunker := (load("res://skill_node/addons/defs/bunker_addon.tscn") as PackedScene).instantiate()
	_f.leaves[0].add_child(bunker)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0], _f.leaves[1]]
	var state := _blade([Vector2(400, 0), Vector2(450, 150)], [0, 0])
	BladeVertexFill.new().fill(state, nodes)
	assert_eq(state.vertex_shielded[1], 1, "the bunker vertex is shielded")
	assert_eq(state.vertex_shielded[2], 0, "a plain vertex is not")


func test_3_on_5_the_piece_spends_3_and_dies() -> void:
	_charge(_f.target, 5.0)
	var res := _spread().resonance
	var state := _blade([Vector2(430, 0)], [3])
	var gate := BladePopResolver.LiveGate.new(state, _f.attacker)
	var c := _contact(gate, 1, _f.target)
	assert_false(gate.admit(c[0], CombatWorld.live()), "the piece dies mid swing")
	assert_true(gate.result.dead_at.has(1))
	assert_eq(state.vertex_charges[1], 0, "the piece spends 3")
	assert_eq(gate.node_charges(_f.target.get_combat()), 5, "the node keeps its 5")
	var row := _only_contact(gate)
	assert_eq(row.striker_power, 3 + 3 * res, "3 + 3r")
	assert_eq(row.node_power, 5 + 3 * res, "5 + 3r")
	assert_eq(row.verdicts[1], BladePopResolver.Contact.Verdict.POPPED, "the striker ends at 0")
