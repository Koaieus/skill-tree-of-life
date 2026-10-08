extends GutTest

## Eagle Eye: one far glance, one big `scouted` stack, no damage.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const EAGLE := preload("res://attack/spell/defs/eagle_eye.tres")
const SCOUTED := preload("res://effects/status/scouted.tres")

var _graph: Graph
var _n: Array[SkillNode]
var _atk: Entity


func before_each() -> void:
	var h := H.new()
	_graph = h.make_graph([[0, 1], [1, 2]], self,
			{0: Vector2.ZERO, 1: Vector2(300, 0), 2: Vector2(500, 0)})
	_atk = h.make_entity(_graph, "A")
	var def := h.make_entity(_graph, "D")
	h.give_big_hp(def)
	h.assign_owner(_graph, def, [1, 2])
	h.assign_owner(_graph, _atk, [0])
	_n = _graph.get_skill_nodes()


func test_lands_innate_scouted_stacks_with_no_damage() -> void:
	var outcome := SpellResolver.resolve(EAGLE, _n[1], _n[0], _atk, _graph)
	var statuses: Array[StatusInstance] = []
	for hit in outcome.hits:
		assert_ne(hit.kind, HitInstance.Kind.DAMAGE, "no damage lands")
		if hit is StatusInstance:
			statuses.append(hit)
	assert_eq(statuses.size(), 1, "one rider on the target")
	if statuses.size() == 1:
		assert_eq(statuses[0].def, SCOUTED)
		assert_eq(statuses[0].power, 8.0, "innate 8 stacks")
		assert_eq(statuses[0].target, _n[1])
		assert_eq(statuses[0].attacker, _atk, "keyed to the caster's camp")


func test_disc_is_larger_than_one_arrow() -> void:
	var scout := SCOUTED as ScoutStatus
	assert_gt(scout.radius_for(_n[1], 8), scout.radius_for(_n[1], 1))
	assert_almost_eq(scout.radius_for(_n[1], 8) / scout.radius_for(_n[1], 1), sqrt(8.0), 0.001)


func test_reach_stops_at_max_distance() -> void:
	var finder := EAGLE.targeting.range_finder as EuclideanRangeFinder
	assert_eq(finder.max_distance, 400.0)
	assert_true(finder.in_range(_atk, _n[0], _n[1]), "300 away is in reach")
	assert_false(finder.in_range(_atk, _n[0], _n[2]), "500 away is beyond reach")
