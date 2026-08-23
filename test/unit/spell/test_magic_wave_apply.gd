extends GutTest

## #501 (descoped): every magic hit gets a real, wave-derived
## `HitInstance.arrival_time` -- 0.0 was a semantic lie under the staged
## presentation clock (docs/domain/attack-timeline.md). Later waves must land
## strictly later so #499's arrival_time sort in OutcomeApplier keeps magic's
## hits in wave order regardless of merge order against volley-499.

var _h: SpellTestHelper


func before_each() -> void:
	_h = SpellTestHelper.new()


func test_arrival_time_is_stamped_and_monotonic_across_waves() -> void:
	var graph := _h.make_graph([[0, 1], [1, 2]], self)
	var nodes := graph.get_skill_nodes()
	var attacker := _h.make_entity(graph, "Attacker", Color.RED)
	var defender := _h.make_entity(graph, "Defender", Color.BLUE)
	_h.give_big_hp(defender)  # nobody dies -- both waves land cleanly
	_h.assign_owner(graph, attacker, [0])
	_h.assign_owner(graph, defender, [1, 2])

	var config := _h.make_config(_h.fan_all(), _h.owner_enemy(), null, {max_hops = 1})
	var spell := _h.make_spell(config, [DamageEffect.new()], 10.0)

	var outcome := SpellResolver.resolve(spell, nodes[1], nodes[0], attacker, graph)

	var by_node := _h.hits_by_node(outcome)
	assert_true(by_node.has(nodes[1]), "seed should have a hit")
	assert_true(by_node.has(nodes[2]), "wave-1 neighbour should have a hit")
	var seed_hit: HitInstance = by_node[nodes[1]][0]
	var hop_hit: HitInstance = by_node[nodes[2]][0]
	assert_gt(hop_hit.arrival_time, seed_hit.arrival_time,
			"a later wave must land strictly after an earlier one")
	# NOT t=0. `arrival_time` is when the hit LANDS, absolutely -- and the seed's
	# own bolt is in the air for `WAVE_FLIGHT_LEAD_IN` first. Landing it at zero
	# put the damage number a whole flight ahead of the projectile; see that
	# constant's doc for why magic was the odd mode out here.
	assert_almost_eq(seed_hit.arrival_time, SpellResolver.WAVE_FLIGHT_LEAD_IN, 0.001,
			"wave 0 (the seed) lands when its bolt arrives, not when it was loosed")


## Same shape, three waves deep, pins the multiplication rather than just
## "later > earlier" -- each wave is one uniform interval further out.
func test_arrival_time_scales_linearly_with_wave_index() -> void:
	var graph := _h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var nodes := graph.get_skill_nodes()
	var attacker := _h.make_entity(graph, "Attacker", Color.RED)
	var defender := _h.make_entity(graph, "Defender", Color.BLUE)
	_h.give_big_hp(defender)
	_h.assign_owner(graph, attacker, [0])
	_h.assign_owner(graph, defender, [1, 2, 3])

	var config := _h.make_config(
			_h.fan_all(), _h.owner_enemy(), null,
			{max_hops = 2, max_visits_per_node = 1})
	var spell := _h.make_spell(config, [DamageEffect.new()], 10.0)

	var outcome := SpellResolver.resolve(spell, nodes[1], nodes[0], attacker, graph)

	var by_node := _h.hits_by_node(outcome)
	var seed_hit: HitInstance = by_node[nodes[1]][0]
	var wave1_hit: HitInstance = by_node[nodes[2]][0]
	var wave2_hit: HitInstance = by_node[nodes[3]][0]
	var interval: float = wave1_hit.arrival_time - seed_hit.arrival_time
	assert_gt(interval, 0.0, "wave interval must be positive")
	assert_almost_eq(wave2_hit.arrival_time - wave1_hit.arrival_time, interval, 0.001,
			"the per-wave interval is uniform")
