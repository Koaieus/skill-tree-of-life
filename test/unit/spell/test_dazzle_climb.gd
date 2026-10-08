extends GutTest

## Dazzle climbs the vision gradient: enemy neighbours at or above the current
## node's node-local vision_range, only the best of them, ties forking.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const DAZZLE := preload("res://attack/spell/defs/dazzle.tres")
const BLINDNESS := preload("res://effects/status/blindness.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _blue: Entity


func _board(adj: Array, red: Array, bonus: Dictionary) -> void:
	_h = H.new()
	_graph = _h.make_graph(adj, self)
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE)
	var red_e := _h.make_entity(_graph, "Red", Color.RED)
	_h.give_big_hp(red_e)
	_h.assign_owner(_graph, red_e, red)
	_h.assign_owner(_graph, _blue, [0])
	_n = _graph.get_skill_nodes()
	for idx in bonus:
		var mod := StatModifier.new()
		mod.stat_id = &"vision_range"
		mod.operation = StatModifier.Operation.ADD_BASE
		mod.value = bonus[idx]
		_n[idx].add_local_modifier(mod)


func _blinded(target_idx: int) -> Dictionary:
	var outcome := SpellResolver.resolve(DAZZLE, _n[target_idx], _n[0], _blue, _graph)
	var hit := {}
	for h in outcome.hits:
		if h is StatusInstance and h.def == BLINDNESS:
			hit[h.target] = true
	return hit


func test_climbs_each_step_up_to_the_watchtower_and_skips_the_low_branch() -> void:
	# 0 caster; line 1-2-3-4; 5 hangs off 2 with lower vision.
	_board([[0, 1], [1, 2], [2, 3], [3, 4], [2, 5]], [1, 2, 3, 4, 5],
			{2: 1.0, 3: 2.0, 4: 6.0, 5: -1.0})
	var hit := _blinded(1)
	for i in [1, 2, 3, 4]:
		assert_true(hit.has(_n[i]), "N%d is blinded" % i)
	assert_false(hit.has(_n[5]), "the lower-vision branch is never entered")


func test_equal_vision_neighbours_both_receive_it() -> void:
	_board([[0, 1], [1, 2], [1, 3]], [1, 2, 3], {2: 2.0, 3: 2.0})
	var hit := _blinded(1)
	assert_true(hit.has(_n[2]), "tie branch A")
	assert_true(hit.has(_n[3]), "tie branch B")
