extends GutTest

## [LocalExtremumCondition]: the landed node's rank is ≥ (MAX) or ≤ (MIN) every
## counted neighbour's, counted by ownership bit and read through the cast's
## world — so an earlier wave's Sunder moves the answer.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SUNDER := preload("res://effects/status/sunder.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _blue: Entity
var _red: Entity


## 0 Blue (caster); 1, 2, 3 Red; 4 unallocated. 1 is the hub: 0, 2, 3, 4 hang off it.
func before_each() -> void:
	_h = H.new()
	_graph = _h.make_graph([[0, 1], [1, 2], [1, 3], [1, 4]], self)
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE)
	_red = _h.make_entity(_graph, "Red", Color.RED)
	_h.give_big_hp(_red)
	_h.assign_owner(_graph, _red, [1, 2, 3])
	_h.assign_owner(_graph, _blue, [0])
	_n = _graph.get_skill_nodes()
	_set_armor(0, 2.0)
	_set_armor(1, 10.0)
	_set_armor(2, 5.0)
	_set_armor(3, 8.0)
	_set_armor(4, 50.0)


func _armor(i: int, world: CombatWorld = CombatWorld.live()) -> float:
	return float(world.combat_for(_n[i]).get_local_value(&"armor"))


func _set_armor(i: int, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value - _armor(i)
	_n[i].add_local_modifier(m)


func _cond(mode: LocalExtremumCondition.Mode, mask: int = -1) -> LocalExtremumCondition:
	var c := LocalExtremumCondition.new()
	c.ranker = _h.stat_ranker(&"armor")
	c.mode = mode
	if mask >= 0:
		c.neighbours = mask
	return c


func _at(c: LocalExtremumCondition, i: int, world: CombatWorld = CombatWorld.live()) -> bool:
	var p := CastSpell.new()
	p.graph = _graph
	p.source = _n[0]
	p.current_node = _n[i]
	var cast := PropagationContext.new()
	cast.graph = _graph
	cast.caster = _blue
	cast.world = world
	return c.evaluate(LandingContext.for_test(p, _n[i], cast))


func test_max_is_true_above_every_counted_neighbour() -> void:
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MAX), 1), "the hub out-armors 0, 2 and 3")


func test_max_is_false_below_a_neighbour() -> void:
	assert_false(_at(_cond(LocalExtremumCondition.Mode.MAX), 2), "2 sits under the hub")
	assert_false(_at(_cond(LocalExtremumCondition.Mode.MAX), 0), "the caster's node sits under the hub")


func test_min_is_the_mirror() -> void:
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MIN), 2), "2 is under its only neighbour")
	assert_false(_at(_cond(LocalExtremumCondition.Mode.MIN), 1), "the hub is above its neighbours")


func test_a_tie_counts_as_an_extremum() -> void:
	_set_armor(2, _armor(1))
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MAX), 1), "≥ every neighbour, ties included")
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MAX), 2), "≥ every neighbour, ties included")


func test_unallocated_neighbours_do_not_count_by_default() -> void:
	assert_gt(_armor(4), _armor(1), "arranged: the unallocated neighbour out-armors the hub")
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MAX), 1), "the default mask skips neutral")
	assert_false(_at(_cond(LocalExtremumCondition.Mode.MAX, 15), 1), "a mask with neutral counts it")


func test_no_counted_neighbour_is_vacuously_an_extremum() -> void:
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MAX, SkillNode.Ownership.NEUTRAL), 2),
			"2's only neighbour is hostile, masked out")


func test_it_reads_armor_lowered_by_an_earlier_waves_sunder() -> void:
	_set_armor(3, 9.0)
	var shadow := CombatWorld.shadow()
	assert_false(_at(_cond(LocalExtremumCondition.Mode.MAX), 3, shadow), "3 sits under the hub before the sunder")
	var sunder := ApplyStatusEffect.new()
	sunder.def = _SUNDER
	sunder.power = 6.0
	var landing := HitLanding.new()
	landing.attacker = _blue
	landing.read_node = _n[0]
	landing.target = _n[1]
	sunder.apply(landing)
	(landing.hits[0] as StatusInstance).land_on(shadow.combat_for(_n[1]), shadow)
	assert_lt(_armor(1, shadow), _armor(3, shadow), "arranged: the sunder broke the hub below 3 in the shadow")
	assert_true(_at(_cond(LocalExtremumCondition.Mode.MAX), 3, shadow), "3 is now the summit in the shadow")
	assert_false(_at(_cond(LocalExtremumCondition.Mode.MAX), 3), "the live world is untouched")
