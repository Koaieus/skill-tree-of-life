extends GutTest

## ArrowVolleyCoordinator presentation-clock reveal (#479/#481):
## Events.damage_shown / Events.node_death_shown must fire on each hit's
## [member DamageInstance.arrival_time] — now the FULL time to impact, launch
## stagger included (#480's distance/speed + RangedAttackPlan's stagger stamp),
## not synchronously with [method play] — mirrors the magic-side clock-contract
## tests in test_magic_bounce_coordinator.gd.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _origin: SkillNode
var _target: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_origin = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_origin.position = Vector2(0, 0)
	_target.position = Vector2(500, 0)
	_graph.add_skill_node(_origin)
	_graph.add_skill_node(_target)


func _mount_coord() -> ArrowVolleyCoordinator:
	var coord := ArrowVolleyCoordinator.new()
	# Visual timing is irrelevant to the reveal schedule — keep it short so
	# the projectile drain doesn't stretch the test.
	coord.flight_time = 0.02
	coord.stagger_per_shot = 0.0
	add_child_autofree(coord)
	return coord


func _hit(arrival_time: float, amount: float = 5.0) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.origin = _origin
	hit.target = _target
	hit.amount = amount
	hit.effective_amount = amount
	hit.arrival_time = arrival_time
	return hit


func test_damage_shown_fires_after_arrival_time_not_synchronously() -> void:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.08))
	var coord := _mount_coord()
	var shown: Array = []
	var handler := func(target: SkillNode, amount: float) -> void:
		shown.append([target, amount])
	Events.damage_shown.connect(handler)
	coord.play(outcome)
	assert_eq(shown.size(), 0, "no reveal synchronously with play() — must wait on arrival_time")
	await get_tree().create_timer(0.08 * 5).timeout
	Events.damage_shown.disconnect(handler)
	assert_eq(shown.size(), 1, "reveal fires once arrival_time has elapsed")
	assert_eq(shown[0][0], _target)
	assert_eq(shown[0][1], 5.0)


func test_farther_hit_reveals_later_than_closer_hit() -> void:
	var near_hit := _hit(0.02)
	var far_hit := _hit(0.10)
	var outcome := AttackOutcome.new()
	outcome.hits.append(far_hit)
	outcome.hits.append(near_hit)
	var coord := _mount_coord()
	var order: Array = []
	var handler := func(target: SkillNode, _amount: float) -> void:
		order.append(target)
	Events.damage_shown.connect(handler)
	coord.play(outcome)
	await get_tree().create_timer(0.05).timeout
	assert_eq(order.size(), 1, "only the closer/faster-arriving hit has revealed so far")
	await get_tree().create_timer(0.10 * 5).timeout
	Events.damage_shown.disconnect(handler)
	assert_eq(order.size(), 2, "both hits have revealed by now")


func test_play_does_not_return_before_all_reveals_fire() -> void:
	# AttackVFX frees the coordinator the instant play() resolves — an early
	# return would silently drop a slow-arrival shot's reveal.
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.03))
	var coord := _mount_coord()
	var shown: Array = []
	var handler := func(target: SkillNode, _amount: float) -> void:
		shown.append(target)
	Events.damage_shown.connect(handler)
	await coord.play(outcome)
	Events.damage_shown.disconnect(handler)
	assert_eq(shown, [_target], "play() only resolved after the reveal fired")


func test_coordinator_never_mutates_hp() -> void:
	var hp_before := _target.get_current_hp()
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.02))
	var coord := _mount_coord()
	await coord.play(outcome)
	assert_eq(_target.get_current_hp(), hp_before,
			"the coordinator must not apply the hit's damage itself")


func test_reveal_waits_for_the_shots_own_launch_stagger() -> void:
	# Recorded arrival_time now INCLUDES the launch stagger — resolve() stamps
	# index * LAUNCH_STAGGER onto the distance/speed flight — and the reveal
	# must ride that recorded number: the launch offset and the reveal are ONE
	# clock, replay-complete (a replay reconstructs the volley from the hits
	# alone). Shot 0: launch 0.00 + flight 0.04. Shot 1: launch 0.20 + flight
	# 0.04 → recorded 0.24. These used to run on two clocks: the arrow flew a
	# flat `flight_time` after `i * stagger_per_shot` while the reveal waited
	# a stagger-free `arrival_time` from t=0 — HP dropped and the damage number
	# popped while later arrows were still leaving the bow.
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.04, 1.0))
	outcome.hits.append(_hit(0.24, 2.0))
	var coord := _mount_coord()
	coord.stagger_per_shot = 0.20
	var shown: Array = []
	var handler := func(_target: SkillNode, amount: float) -> void:
		shown.append(amount)
	Events.damage_shown.connect(handler)
	coord.play(outcome)

	# Past shot 0's own impact (0.00 launch + 0.04 flight), well short of
	# shot 1's (0.20 launch + 0.04 flight).
	await get_tree().create_timer(0.12).timeout
	assert_eq(shown.size(), 1,
			"the second shot has not landed yet — its reveal must wait its turn")
	assert_eq(shown[0], 1.0, "and the one that did land is the first shot")

	await get_tree().create_timer(0.30).timeout
	Events.damage_shown.disconnect(handler)
	assert_eq(shown.size(), 2, "the staggered shot reveals when its own arrow arrives")


func test_flight_matches_the_shots_arrival_time() -> void:
	# The arrow's airtime IS the reveal's schedule — a far shot visibly takes
	# longer than a near one, instead of every arrow flying for a flat duration
	# while the reveals used distance/speed. arrival_time now INCLUDES the
	# launch stagger; _flight_for strips this shot's own launch_delay back out
	# so the arrow lands at the recorded time.
	var coord := _mount_coord()
	coord.flight_time = 0.10
	assert_almost_eq(coord._flight_for(_hit(0.40), 0.0), 0.40, 0.0001,
			"a real arrival time drives the arrow directly")
	assert_almost_eq(coord._flight_for(_hit(0.0), 0.0), 0.10, 0.0001,
			"no arrival time falls back to the authored flight_time")
	assert_almost_eq(coord._flight_for(_hit(0.001), 0.0),
			0.10 * ArrowVolleyCoordinator.MIN_FLIGHT_FRACTION, 0.0001,
			"a point-blank shot is floored so it still reads as an arrow")
	assert_almost_eq(coord._flight_for(_hit(0.50), 0.10), 0.40, 0.0001,
			"the shot's own launch stagger is stripped back out of the airtime")
