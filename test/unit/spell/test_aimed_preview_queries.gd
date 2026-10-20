extends GutTest

## The aimed preview asks for its seeds at most once per aim change (#1704):
## a burst of [signal AttackPlan.state_changed] with the same (source, angle)
## re-reads the kept crossed set instead of gathering again.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


## N0 (A's core) - N1 (A) - N2 (neutral) - N3 - N4 (D's), east along y = 0.
func _plan() -> MagicAttackPlan:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4]], self, {
		0: Vector2.ZERO, 1: Vector2(100, 0), 2: Vector2(200, 0),
		3: Vector2(300, 0), 4: Vector2(400, 0),
	})
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, atk, [0, 1])
	helper.assign_owner(graph, def, [4, 3])
	var config := helper.make_config(helper.no_spread(), helper.owner_enemy(), helper.sum_reducer())
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var t := AimedTargeting.new()
	t.shape = LineShape.new()
	t.ownership_filter = 8
	t.range_finder = EuclideanRangeFinder.new()
	t.range_finder.max_distance = 450.0
	spell.targeting = t
	var plan := MagicAttackPlan.new()
	plan.attacker = atk
	plan.set_spell(spell)
	assert_true(plan.set_aim(graph.get_skill_nodes()[1], 0.0), "the aim takes")
	return plan


func test_unchanged_aim_costs_one_seed_query() -> void:
	var plan := _plan()
	plan.preview_outcome()
	var base := plan.preview_seed_queries
	assert_eq(base, 1, "the first preview gathers once")
	for i in 5:
		plan.state_changed.emit()
		plan.preview_outcome()
	assert_eq(plan.preview_seed_queries, base, "five rebuilds at the same aim, no new gather")
	assert_true(plan.set_aim(plan.source, 0.05), "a nudged angle")
	plan.preview_outcome()
	assert_eq(plan.preview_seed_queries, base + 1, "a changed angle gathers once more")


func test_invalidation_regathers_at_the_same_aim() -> void:
	var plan := _plan()
	plan.preview_outcome()
	var base := plan.preview_seed_queries
	plan.invalidate_union()
	plan.preview_outcome()
	assert_eq(plan.preview_seed_queries, base + 1, "an ownership/turn change re-gathers")
