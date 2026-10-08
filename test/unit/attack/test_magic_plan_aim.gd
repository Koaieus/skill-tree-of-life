extends GutTest

## An aimed spell on [MagicAttackPlan] (#1496): the plan owns the aim
## (source + [member MagicAttackPlan.aim_angle]), carries it on the wire, and
## resolves it through [method SpellResolver.resolve_seeds]; the AI aims each
## (source, reachable node) pair at that node.

const H := preload("res://test/unit/spell/spell_test_helper.gd")

## The catalog holds no aimed spell yet, and [method MagicAttackPlan.from_dict]
## looks the spell up there — so the round trip borrows SPARK and aims it,
## restored after every test.
var _spark_targeting: Targeting
## Through a var: GDScript refuses a property write on a const's resource.
var _spark: SpellDef = SpellCatalog.SPARK


func before_each() -> void:
	_spark_targeting = _spark.targeting


func after_each() -> void:
	_spark.targeting = _spark_targeting


func _aimed(filter: int = 8, length: float = 450.0) -> AimedTargeting:
	var t := AimedTargeting.new()
	t.shape = LineShape.new()
	t.ownership_filter = filter
	t.range_finder = EuclideanRangeFinder.new()
	t.range_finder.max_distance = length
	return t


func _nodes(graph: Graph) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	out.assign(graph.get_skill_nodes())
	return out


## N0 (A's core) - N1 (A) - N2 (neutral) - N3 - N4 (D's), east along y = 0.
func _board() -> Array:
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
	spell.targeting = _aimed()
	return [graph, atk, spell]


func _plan(atk: Entity, spell: SpellDef) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = atk
	plan.set_spell(spell)
	return plan


func _hit_set(outcome: AttackOutcome) -> Array[String]:
	var out: Array[String] = []
	for ev in outcome.timeline:
		if ev.target != null and not ev.hits.is_empty() and not out.has(String(ev.target.name)):
			out.append(String(ev.target.name))
	out.sort()
	return out


func test_aimed_plan_round_trips_source_spell_and_angle() -> void:
	var fx := _board()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	_spark.targeting = _aimed()
	var plan := _plan(fx[1], SpellCatalog.SPARK)
	assert_true(plan.set_aim(n[0], 0.25), "N0 is an eligible caster")
	var d := plan.to_dict(graph)
	assert_true(d.has("aim"), "an aimed plan carries its angle")
	var back := MagicAttackPlan.from_dict(d, graph)
	assert_eq(back.source, n[0])
	assert_eq(back.spell, SpellCatalog.SPARK)
	assert_almost_eq(back.aim_angle, 0.25, 0.000001)
	assert_null(back.target)


func test_node_targeted_plan_dict_has_no_aim_key() -> void:
	var fx := _board()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var plan := MagicAttackPlan.new()
	plan.attacker = fx[1]
	plan.spell = SpellCatalog.SPARK
	plan.source = n[1]
	plan.target = n[3]
	assert_false(plan.to_dict(graph).has("aim"))


func test_set_target_refused_on_an_aimed_plan() -> void:
	var fx := _board()
	var n := _nodes(fx[0])
	var plan := _plan(fx[1], fx[2])
	assert_false(plan.set_target(n[3]), "an aimed spell is dragged, never clicked")
	assert_null(plan.target)
	assert_null(plan.source)


func test_set_aim_refuses_an_ineligible_source_and_leaves_the_plan() -> void:
	var fx := _board()
	var n := _nodes(fx[0])
	var plan := _plan(fx[1], fx[2])
	assert_false(plan.set_aim(n[3], 1.0), "N3 is the defender's")
	assert_null(plan.source)
	assert_true(is_nan(plan.aim_angle))
	assert_true(plan.set_aim(n[0], 0.5))
	assert_false(plan.set_aim(n[4], 1.0))
	assert_eq(plan.source, n[0])
	assert_almost_eq(plan.aim_angle, 0.5, 0.000001)
	assert_true(plan.validate().is_empty(), "source + aim is a complete aimed plan")


func test_set_aim_refused_on_a_node_targeted_spell() -> void:
	var fx := _board()
	var n := _nodes(fx[0])
	var spell: SpellDef = fx[2]
	spell.targeting = NodeTargeting.new()
	var plan := _plan(fx[1], spell)
	assert_false(plan.set_aim(n[0], 0.0))
	assert_true(is_nan(plan.aim_angle))


func test_resolve_against_matches_resolve_seeds_directly() -> void:
	var fx := _board()
	var graph: Graph = fx[0]
	var n := _nodes(graph)
	var spell: SpellDef = fx[2]
	var plan := _plan(fx[1], spell)
	assert_true(plan.set_aim(n[0], 0.0))
	var via_plan := plan.resolve()
	var seeds := (spell.targeting as AimedTargeting).seeds(fx[1], n[0], 0.0, graph)
	var world := CombatWorld.shadow()
	var direct := SpellResolver.resolve_seeds(spell, seeds, n[0], fx[1], graph, world,
			plan.seeded_rng(), plan.infusion, 0.0)
	world.free_shadow()
	assert_eq(_hit_set(via_plan), ["N3", "N4"] as Array[String])
	assert_eq(_hit_set(via_plan), _hit_set(direct))
	assert_not_null(via_plan.aim, "the outcome records the aim it resolved under")


func test_ai_aims_a_candidate_and_arms_a_valid_plan() -> void:
	var fx := _board()
	var n := _nodes(fx[0])
	var atk: Entity = fx[1]
	var ai := AIController.new()
	ai.turn_delay = 0.0
	atk.add_child(ai)
	atk.get_spellbook().learn(fx[2])
	var visible: Array[SkillNode] = [n[3], n[4]]
	var candidates := ai._gather_magic_candidates(visible)
	assert_gt(candidates.size(), 0, "an aimed spell yields candidates")
	if candidates.is_empty():
		return
	var c := candidates[0]
	assert_false(is_nan(c.aim_angle), "the candidate carries its aim")
	var plan := MagicAttackPlan.new()
	plan.attacker = atk
	ai._arm_magic_plan(plan, c)
	assert_null(plan.target)
	assert_eq(plan.validate(), [] as Array[String])
