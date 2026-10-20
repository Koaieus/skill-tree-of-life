extends GutTest

## Malediction (#1560): Curse's rumour. The main payload flows downhill by the
## node-local `min_damage_taken` (ties fork); every other enemy neighbour
## takes a floored off-path share and carries nothing on; a node visited twice
## holds both visits' stacks.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const MALEDICTION: SpellDef = preload("res://attack/spell/defs/malediction.tres")
const CURSE := preload("res://effects/status/curse.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _blue: Entity


## Node 0 is the caster's; [param red] are the enemy's; [param floor_bonus]
## shifts a node's local `min_damage_taken` (index -> delta).
func _board(adj: Array, red: Array, floor_bonus: Dictionary) -> void:
	_h = H.new()
	_graph = _h.make_graph(adj, self)
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE)
	var red_e := _h.make_entity(_graph, "Red", Color.RED)
	_h.give_big_hp(red_e)
	_h.assign_owner(_graph, red_e, red)
	_h.assign_owner(_graph, _blue, [0])
	_n = _graph.get_skill_nodes()
	for idx in floor_bonus:
		var mod := StatModifier.new()
		mod.stat_id = &"min_damage_taken"
		mod.operation = StatModifier.Operation.ADD_BASE
		mod.value = floor_bonus[idx]
		_n[idx].add_local_modifier(mod)


## Every curse landing per node: SkillNode -> Array[float] of landed stacks.
func _cursed(target_idx: int, spell: SpellDef = MALEDICTION) -> Dictionary:
	var outcome := SpellResolver.resolve(spell, _n[target_idx], _n[0], _blue, _graph)
	var out := {}
	for h in outcome.hits:
		if h is StatusInstance and h.def == CURSE:
			var arr: Array = out.get(h.target, [])
			arr.append(h.power)
			out[h.target] = arr
	return out


func _innate() -> float:
	return float(MALEDICTION.intakes[0].innate)


func test_main_payload_follows_the_lower_floor_and_siblings_take_a_terminal_minor_share() -> void:
	# 0 caster; 1 the target; 2 lower floor, 3 and 4 siblings at the base floor.
	# 5 hangs off 2 at 2's floor (the rumour continues); 6 and 7 hang off the
	# siblings (the rumour must never reach them).
	_board([[0, 1], [1, 2], [1, 3], [1, 4], [2, 5], [3, 6], [4, 7]],
			[1, 2, 3, 4, 5, 6, 7], {2: -1.0, 5: -1.0})
	var hit := _cursed(1)
	assert_true(hit.has(_n[2]), "the lower floor takes the main payload")
	assert_eq(hit.get(_n[2], [0.0])[0], _innate(), "…at full stacks")
	assert_true(hit.has(_n[5]), "the main payload keeps flowing downhill")
	for i in [3, 4]:
		assert_true(hit.has(_n[i]), "sibling %d takes the off-path share" % i)
		var landed: float = hit.get(_n[i], [999.0])[0]
		assert_gt(landed, 0.0, "the off-path share lands something on %d" % i)
		assert_lt(landed, _innate(), "…smaller than the winners' on %d" % i)
	for i in [6, 7]:
		assert_false(hit.has(_n[i]), "nothing propagates from an off-path node (%d)" % i)


func test_an_off_path_share_below_one_reaches_the_event() -> void:
	# arrival_share is per-arc telemetry for every spell, not Cyclone's alone:
	# a sibling's minor share must reach PropagationEvent.incident_shares.
	_board([[0, 1], [1, 2], [1, 3], [1, 4]], [1, 2, 3, 4], {2: -1.0})
	var outcome := SpellResolver.resolve(MALEDICTION, _n[1], _n[0], _blue, _graph)
	var share := -1.0
	for ev in outcome.timeline:
		if ev.target == _n[3] and ev.incident_shares.size() == 1:
			share = ev.incident_shares[0]
	assert_gt(share, 0.0, "the sibling's arc reports its share")
	assert_lt(share, 1.0, "…and it is the minor share, not a default 1.0")


func test_tied_lowest_floors_fork_at_full_share() -> void:
	_board([[0, 1], [1, 2], [1, 3], [1, 4]], [1, 2, 3, 4], {2: -1.0, 3: -1.0})
	var hit := _cursed(1)
	for i in [2, 3]:
		assert_true(hit.has(_n[i]), "tied branch %d" % i)
		assert_eq(hit.get(_n[i], [0.0])[0], _innate(), "tied branch %d takes a full share" % i)
	assert_lt(hit.get(_n[4], [999.0])[0], _innate(), "the higher floor only takes the minor share")


func test_a_node_reached_twice_holds_both_visits_stacks() -> void:
	# Flat diamond: 2 and 3 both reach 4 on the same wave.
	_board([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [1, 2, 3, 4], {})
	var hit := _cursed(1)
	var landed: Array = hit.get(_n[4], [])
	assert_false(landed.is_empty(), "the far node is cursed")
	assert_eq(landed.max() if not landed.is_empty() else 0.0, 2.0 * _innate(),
			"two arrivals land both payloads' stacks")
	var total := 0.0
	for p in hit.get(_n[1], []):
		total += p
	assert_gt(total, _innate(), "the target, revisited, holds more than one visit's stacks")


func test_an_off_path_share_flooring_to_zero_is_not_visited() -> void:
	var weak: SpellDef = MALEDICTION.duplicate()
	var aff: AspectIntake = MALEDICTION.intakes[0].duplicate()
	aff.innate = 3
	var affs: Array[AspectIntake] = [aff]
	weak.intakes = affs
	_board([[0, 1], [1, 2], [1, 3], [1, 4]], [1, 2, 3, 4], {2: -1.0})
	var outcome := SpellResolver.resolve(weak, _n[1], _n[0], _blue, _graph)
	var reached := {}
	for ev in outcome.timeline:
		reached[ev.target] = true
	for h in outcome.hits:
		reached[h.target] = true
	assert_true(reached.has(_n[2]), "the winner is still reached")
	var off_path: Array = []
	for i in [3, 4]:
		if reached.has(_n[i]):
			off_path.append(i)
	assert_eq(off_path, [], "3 x 0.25 floors to 0: the losers are never visited")


func test_a_node_both_won_and_lost_on_one_wave_still_carries_the_rumour() -> void:
	# 1 -> P(2), Q(3) tied; P -> A(4), Q -> B(5); A and B both reach X(6) on
	# one wave: X is downhill from A (a winner) but uphill from B (an off-path
	# terminal). The winner's arc must survive the merge and reach Y(7).
	_board([[0, 1], [1, 2], [1, 3], [2, 4], [3, 5], [4, 6], [5, 6], [6, 7]],
			[1, 2, 3, 4, 5, 6, 7], {2: -1.0, 3: -1.0, 4: -1.0, 5: -3.0, 6: -2.0, 7: -2.0})
	var hit := _cursed(1)
	assert_true(hit.has(_n[6]), "X is cursed")
	assert_true(hit.has(_n[7]), "the winning arc into X keeps flowing past the terminal one")


func test_no_spell_answers_to_the_old_hex_id() -> void:
	for spell in SpellCatalog.ALL:
		assert_ne(spell.id, &"hex", "the shipped hex is Malediction now")
	assert_eq(MALEDICTION.id, &"malediction")
