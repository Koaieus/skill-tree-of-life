extends GutTest

## Every carrier that lands `scouted` is a lantern while it is drawn: each
## scout arrow, a scout spell's bolt, and the scout_line streak's tip. The
## coordinator decides; [Projectile] / [HitscanStreak] stay scout-unaware.

const _ARROW_COORD := preload("res://ui/vfx/coordinator/arrow_volley_coordinator.tscn")
const _SCOUT_LINE_COORD := preload("res://ui/vfx/coordinator/spells/scout_line_coordinator.tscn")
const _SPARK_COORD := preload("res://ui/vfx/coordinator/spells/spark_coordinator.tscn")
const _SCOUT_LINE := preload("res://attack/spell/defs/scout_line.tres")
const _EAGLE_EYE := preload("res://attack/spell/defs/eagle_eye.tres")
const H := preload("res://test/unit/spell/spell_test_helper.gd")

var _graph: Graph
var _origin: SkillNode
var _target: SkillNode
var _attacker: Entity


func before_each() -> void:
	var world := TestWorld.create(self)
	_graph = world.graph
	_origin = world.add_node(&"", Vector2.ZERO)
	_target = world.add_node(&"", Vector2(500, 0))
	_attacker = autofree(Entity.new())


func _arrow_hit(ammo_id: StringName) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.origin = _origin
	hit.target = _target
	hit.attacker = _attacker
	hit.ammo_type_id = ammo_id
	hit.amount = 1.0
	return hit


func _lanterns_of(node: Node) -> Array[Lantern]:
	var out: Array[Lantern] = []
	for child in node.get_children():
		if child is Lantern:
			out.append(child)
	return out


func _projectiles_of(coord: Node) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in coord.get_children():
		if child is Projectile:
			out.append(child)
	return out


func _tempo(lead_in: float) -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.beat_interval = lead_in
	tempo.beat_lead_in = lead_in
	return tempo


func _volley(ids: Array[StringName]) -> Array[Projectile]:
	var coord := _ARROW_COORD.instantiate() as ArrowVolleyCoordinator
	coord.flight_time = 0.02
	add_child_autofree(coord)
	var outcome := AttackOutcome.new()
	for id in ids:
		outcome.hits.append(_arrow_hit(id))
	coord.play(outcome)
	return _projectiles_of(coord)


func test_every_scout_arrow_carries_one_lantern_of_the_attacker() -> void:
	var projs := _volley([&"scout", &"scout", &"scout"])
	assert_eq(projs.size(), 3, "fixture: three arrows")
	for proj in projs:
		var lanterns := _lanterns_of(proj)
		assert_eq(lanterns.size(), 1, "one lantern per scout arrow")
		if lanterns.size() == 1:
			assert_eq(lanterns[0].source, _attacker)
			assert_gt(lanterns[0].radius, 0.0)


func test_a_non_scout_and_the_base_arrow_carry_none() -> void:
	var projs := _volley([&"poison", &""])
	assert_eq(projs.size(), 2, "fixture: two arrows")
	for proj in projs:
		assert_eq(_lanterns_of(proj).size(), 0)


func test_a_parked_scout_arrow_keeps_one_lantern_through_release() -> void:
	var coord := _ARROW_COORD.instantiate() as ArrowVolleyCoordinator
	coord.flight_time = 0.02
	add_child_autofree(coord)
	var outcome := AttackOutcome.new()
	outcome.hits.append(_arrow_hit(&"scout"))
	outcome.hits.append(_arrow_hit(&"scout"))
	coord.outcome = outcome
	var tempo := PresentationTempo.new()
	tempo.volley_draw_time = 0.1
	assert_gt(coord.begin_windup(RangedAttackPlan.new(), tempo), 0.0, "fixture: wind-up parks")
	coord.play(outcome)
	var projs := _projectiles_of(coord)
	assert_eq(projs.size(), 2, "the parked arrows are the ones released")
	for proj in projs:
		assert_eq(_lanterns_of(proj).size(), 1, "parked + released = still one lantern")


func _scout_line_streak() -> HitscanStreak:
	var coord := _SCOUT_LINE_COORD.instantiate() as MagicBounceCoordinator
	coord.tempo = _tempo(0.3)
	coord.clock = BeatClock.instant_clock()
	coord.spell = _SCOUT_LINE
	coord.caster_entity = _attacker
	add_child_autofree(coord)
	var outcome := AttackOutcome.new()
	outcome.aim = AttackOutcome.Aim.new()
	outcome.aim.origin = _origin
	outcome.aim.angle = 0.0
	outcome.aim.length = 400.0
	coord.play(outcome)
	for child in coord.get_children():
		if child is HitscanStreak:
			return child
	return null


func test_the_scout_line_lantern_rides_the_streak_tip_then_leaves() -> void:
	var streak := _scout_line_streak()
	assert_not_null(streak, "fixture: the aim draws a streak")
	if streak == null:
		return
	var lanterns := _lanterns_of(streak)
	assert_eq(lanterns.size(), 1, "the streak carries one lantern")
	if lanterns.size() != 1:
		return
	var lantern := lanterns[0]
	assert_eq(lantern.source, _attacker)
	var samples: Array[Vector2] = []
	for wait in [0.08, 0.1]:
		await wait_seconds(wait)
		var tip := streak.to_global(streak.get_point_position(1))
		assert_almost_eq(lantern.global_position.distance_to(tip), 0.0, 1.0,
				"the lantern sits on the tip")
		samples.append(tip)
	assert_gt(samples[1].x, samples[0].x, "the tip travelled between samples")
	await wait_for_signal(streak.tree_exited, 2.0)
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group(Lantern.GROUP).size(), 0,
			"no marker outlives the streak")


func test_a_non_scout_streak_carries_no_lantern() -> void:
	var coord := _SCOUT_LINE_COORD.instantiate() as MagicBounceCoordinator
	coord.tempo = _tempo(0.3)
	coord.clock = BeatClock.instant_clock()
	add_child_autofree(coord)
	var outcome := AttackOutcome.new()
	outcome.aim = AttackOutcome.Aim.new()
	outcome.aim.origin = _origin
	outcome.aim.length = 400.0
	coord.play(outcome)
	for child in coord.get_children():
		if child is HitscanStreak:
			assert_eq(_lanterns_of(child).size(), 0)


func test_the_eagle_eye_bolt_carries_a_lantern() -> void:
	var h := H.new()
	var graph := h.make_graph([[0, 1]], self, {0: Vector2.ZERO, 1: Vector2(300, 0)})
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.assign_owner(graph, def, [1])
	h.assign_owner(graph, atk, [0])
	var nodes := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_EAGLE_EYE, nodes[1], nodes[0], atk, graph)
	var jumps := outcome.timeline.filter(func(ev: PropagationEvent) -> bool:
		return ev.verb == PropagationEvent.Verb.JUMP)
	assert_eq(jumps.size(), 1, "fixture: eagle_eye draws one JUMP bolt")
	var coord := _SPARK_COORD.instantiate() as MagicBounceCoordinator
	coord.tempo = _tempo(0.3)
	coord.clock = BeatClock.instant_clock()
	coord.spell = _EAGLE_EYE
	add_child_autofree(coord)
	coord.play(outcome)
	var projs := _projectiles_of(coord)
	assert_eq(projs.size(), 1, "one bolt in flight")
	for proj in projs:
		var lanterns := _lanterns_of(proj)
		assert_eq(lanterns.size(), 1, "the bolt carries one lantern")
		if lanterns.size() == 1:
			assert_eq(lanterns[0].source, atk, "the caster, read off the hits")
