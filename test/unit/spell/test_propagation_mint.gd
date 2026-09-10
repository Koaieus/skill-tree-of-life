extends GutTest

## #852 — the departure seam split in two: a [PropagationSpread] SELECTS
## picks and [PropagationConfig.mint] BUILDS the child. These pin each half
## on its own:
##   - `mint`: progression × share, hop counters, lineage, and the pick's
##     stamps copied verbatim;
##   - `FanAllSpread.select`: one full-share pick per eligible node, payload
##     untouched;
##   - `CycloneSpread.select`: the picks carry exactly the shares the old
##     `CycloneStep` folded into `damage` — rank coefficient, closing gain on
##     a closing hop — so the split moved WHERE the multiply happens and
##     nothing else (`test_cyclone.gd` is the end-to-end golden for that).

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _CYCLONE := preload("res://attack/spell/defs/cyclone.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = H.new()


func _ctx(graph: Graph) -> PropagationContext:
	var c := PropagationContext.new()
	c.graph = graph
	return c


func _payload(current: SkillNode, damage: float, seed_damage: float = -1.0) -> CastSpell:
	var p := CastSpell.new()
	p.seed_node = current
	p.current_node = current
	p.source = current
	p.damage = damage
	p.seed_damage = seed_damage if seed_damage >= 0.0 else damage
	p.hops_remaining = 4
	p.hop_index = 2
	p.visited = [current] as Array[SkillNode]
	p.rng = RandomNumberGenerator.new()
	p.graph = current.get_parent().get_parent() if current.get_parent() != null else null
	return p


# ── PropagationConfig.mint ────────────────────────────────────────────────

func test_mint_applies_progression_then_share() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null, {hop_damage = h.flat_add_progression(2.0)})
	var child := config.mint(_payload(nodes[0], 10.0), PropagationPick.to(nodes[1], 0.5))
	assert_almost_eq(child.damage, (10.0 + 2.0) * 0.5, 0.0001,
			"progression first (10 + 2), THEN the pick's share (× 0.5)")
	assert_almost_eq(child.arrival_share, 0.5, 0.0001, "arrival_share IS the pick's share")


func test_mint_without_progression_carries_damage_times_share() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null)
	var child := config.mint(_payload(nodes[0], 7.0), PropagationPick.to(nodes[1]))
	assert_almost_eq(child.damage, 7.0, 0.0001, "null progression is identity, share 1.0 is identity")


func test_mint_advances_hop_counters_and_identity_fields() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null)
	var parent := _payload(nodes[0], 3.0, 9.0)
	var child := config.mint(parent, PropagationPick.to(nodes[1]))
	assert_eq(child.hops_remaining, 3, "hops_remaining - 1")
	assert_eq(child.hop_index, 3, "hop_index + 1")
	assert_eq(child.current_node, nodes[1])
	assert_eq(child.predecessor, nodes[0], "predecessor is the node it left")
	assert_eq(child.seed_node, nodes[0])
	assert_eq(child.source, nodes[0])
	assert_almost_eq(child.seed_damage, 9.0, 0.0001, "seed_damage copied verbatim")
	assert_same(child.rng, parent.rng, "rng threaded through")


func test_mint_appends_destination_to_a_copied_lineage() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null)
	var parent := _payload(nodes[0], 3.0)
	var child := config.mint(parent, PropagationPick.to(nodes[1]))
	assert_eq(child.visited, [nodes[0], nodes[1]] as Array[SkillNode], "parent trail + destination")
	assert_eq(parent.visited.size(), 1, "the parent's own trail is untouched (copied, not aliased)")


func test_mint_lineage_override_replaces_the_trail() -> void:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 0]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null)
	var pick := PropagationPick.to(nodes[0])
	pick.lineage_override = [nodes[1], nodes[2], nodes[0]] as Array[SkillNode]
	var child := config.mint(_payload(nodes[2], 3.0), pick)
	assert_eq(child.visited, pick.lineage_override, "a closing pick hands the ring over as the whole trail")


func test_mint_copies_pick_stamps_verbatim() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null)
	var pick := PropagationPick.to(nodes[1], 0.7)
	pick.arrival_bearing = Vector2(0.6, 0.8)
	pick.turn_sign = -1.0
	pick.closed_cycle = true
	pick.came_from = [nodes[0]] as Array[SkillNode]
	var child := config.mint(_payload(nodes[0], 3.0), pick)
	assert_eq(child.arrival_bearing, Vector2(0.6, 0.8))
	assert_almost_eq(child.turn_sign, -1.0, 0.0001)
	assert_true(child.closed_cycle)
	assert_eq(child.came_from, [nodes[0]] as Array[SkillNode])


func test_mint_defaults_leave_non_curl_children_unstamped() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), null, null)
	var child := config.mint(_payload(nodes[0], 3.0), PropagationPick.to(nodes[1]))
	assert_eq(child.arrival_bearing, Vector2.ZERO)
	assert_almost_eq(child.turn_sign, 0.0, 0.0001)
	assert_false(child.closed_cycle)
	assert_true(child.came_from.is_empty())


# ── FanAllSpread.select ───────────────────────────────────────────────────

func test_fan_all_selects_every_eligible_at_full_share_without_touching_payload() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var nodes := graph.get_skill_nodes()
	var eligible := [nodes[1], nodes[2], nodes[3]] as Array[SkillNode]
	var payload := _payload(nodes[0], 5.0)
	var picks := FanAllSpread.new().select(nodes[0], eligible, payload, _ctx(graph))
	assert_eq(picks.size(), 3, "one pick per eligible node")
	for i in picks.size():
		assert_eq(picks[i].node, eligible[i], "in eligible order")
		assert_almost_eq(picks[i].share, 1.0, 0.0001, "full share")
	assert_almost_eq(payload.damage, 5.0, 0.0001, "select never does damage math")
	assert_eq(payload.hops_remaining, 4, "select never writes hops_remaining")
	assert_eq(payload.visited.size(), 1, "select never touches the lineage")


# ── CycloneSpread.select ──────────────────────────────────────────────────

func _polar(i: int, n: int, r: float = 60.0) -> Vector2:
	var a := TAU * float(i) / float(n)
	return Vector2(cos(a), sin(a)) * r


func test_cyclone_select_shares_are_the_rank_coefficients_in_turn_order() -> void:
	# A hub (0) with five spokes on a circle; the front arrived from spoke 5.
	var adj := [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
	var pos := {0: Vector2.ZERO}
	for i in range(1, 6):
		pos[i] = _polar(i - 1, 5)
	var graph := h.make_graph(adj, self, pos)
	var nodes := graph.get_skill_nodes()
	var spread: CycloneSpread = (_CYCLONE.propagation as PropagationConfig).spread.duplicate(true)
	var payload := _payload(nodes[0], 10.0)
	payload.predecessor = nodes[5]
	payload.visited = [nodes[5], nodes[0]] as Array[SkillNode]
	var eligible := [nodes[1], nodes[2], nodes[3], nodes[4]] as Array[SkillNode]

	var picks := spread.select(nodes[0], eligible, payload, _ctx(graph))

	var ranked := Curl.rank(nodes[5].global_position, nodes[0], eligible, spread.clockwise)
	assert_eq(picks.size(), spread.rank_coefficients.size(), "one pick per authored rank")
	for r in picks.size():
		assert_eq(picks[r].node, ranked[r], "rank %d is the %dth sharpest turn" % [r, r])
		assert_almost_eq(picks[r].share, spread.rank_coefficients[r], 0.0001,
				"rank %d carries c_%d, exactly what CycloneStep multiplied damage by" % [r, r + 1])
		assert_false(picks[r].closed_cycle)
		assert_eq(picks[r].came_from, [nodes[0]] as Array[SkillNode])
		assert_almost_eq(picks[r].turn_sign, 1.0 if spread.clockwise else -1.0, 0.0001)
		assert_almost_eq(picks[r].arrival_bearing.length(), 1.0, 0.0001, "a heading, not a displacement")
	assert_almost_eq(payload.damage, 10.0, 0.0001, "select never multiplied the payload")


func test_cyclone_select_closing_hop_folds_closing_gain_into_share_and_hands_over_the_ring() -> void:
	# Triangle 0-1-2; the front walked 0 → 1 → 2 and node 0 is eligible again.
	var pos := {0: Vector2(0, 0), 1: Vector2(60, 0), 2: Vector2(30, 52)}
	var graph := h.make_graph([[0, 1], [1, 2], [2, 0]], self, pos)
	var nodes := graph.get_skill_nodes()
	var spread: CycloneSpread = (_CYCLONE.propagation as PropagationConfig).spread.duplicate(true)
	var payload := _payload(nodes[2], 10.0)
	payload.predecessor = nodes[1]
	payload.visited = [nodes[0], nodes[1], nodes[2]] as Array[SkillNode]

	var picks := spread.select(nodes[2], [nodes[0]] as Array[SkillNode], payload, _ctx(graph))

	assert_eq(picks.size(), 1)
	var pick := picks[0]
	assert_true(pick.closed_cycle, "landing on 0 closes 0-1-2")
	assert_almost_eq(pick.share, spread.rank_coefficients[0] * spread.closing_gain, 0.0001,
			"c_1 × closing_gain — the sustain term rides the share")
	assert_true(pick.came_from.is_empty(), "a closer clears came_from")
	assert_eq(pick.lineage_override, CycloneSpread.closed_ring(payload.visited, 0),
			"the ring the hop just walked, ending at the landed node")
	# And the mint honours it: the child's trail IS the ring, damage IS the split.
	var child := (_CYCLONE.propagation as PropagationConfig).mint(payload, pick)
	assert_eq(child.visited, pick.lineage_override)
	assert_almost_eq(child.arrival_share, pick.share, 0.0001)
