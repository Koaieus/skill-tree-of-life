extends GutTest

## ArrowVolleyCoordinator as a PURE OBSERVER (#474/#504).
##
## This file used to pin the coordinator's own reveal schedule: `damage_shown`
## firing per shot at its `arrival_time`. #504 deleted that clock — the world
## now mutates at `arrival_time` in [OutcomeApplier], and every painter reads
## the model, so the coordinator draws arrows and announces nothing. Those
## timing assertions moved to where the timing lives:
## `test_outcome_applier_beat_clock.gd`.
##
## What remains testable here is the observer contract itself: the coordinator
## renders a volley without ever touching the world, and does not return (and
## so get freed by [AttackVFX]) while arrows are still in flight.

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


func test_coordinator_never_mutates_hp() -> void:
	var hp_before := _target.get_current_hp()
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.02))
	var coord := _mount_coord()
	await coord.play(outcome)
	assert_eq(_target.get_current_hp(), hp_before,
			"the coordinator must not apply the hit's damage itself")


func test_one_projectile_per_shot() -> void:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.02))
	outcome.hits.append(_hit(0.04))
	outcome.hits.append(_hit(0.06))
	var coord := _mount_coord()
	coord.play(outcome)
	var projectiles := coord.get_children().filter(func(c): return c is Projectile)
	assert_eq(projectiles.size(), 3, "one arrow per scheduled shot")
	await coord.play(outcome)


func test_play_does_not_return_before_arrows_drain() -> void:
	# AttackVFX frees the coordinator the instant play() resolves, so an early
	# return would cut the volley off mid-flight. The drain is a teardown
	# guard, NOT a gameplay gate: BattleSystem starts play() un-awaited and the
	# mutation loop never waits on it (see BeatClock).
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(0.03))
	var coord := _mount_coord()
	await coord.play(outcome)
	var still_flying := coord.get_children().filter(func(c): return c is Projectile)
	assert_eq(still_flying.size(), 0, "play() only resolved once every arrow was done")


## docs/domain/attack-timeline.md flags `_flight_for`'s MIN_FLIGHT_FRACTION
## clamp as the drift class #479/#481 cost five rounds of latches, and #504
## RAISES the stakes: the arrow's flight is now the only thing keeping the
## visual in step with a mutation that happens at `arrival_time`. If the clamp
## bites, the arrow lands EARLY and the damage arrives after it — visibly.
##
## With the shipped constants it cannot: every shot flies
## `RangedDamageFormula.FLIGHT_TIME` (0.35s) against a floor of
## `flight_time * MIN_FLIGHT_FRACTION` (0.45 * 0.4 = 0.18s). This pins the
## relationship so retuning either constant fails here instead of on screen.
func test_flight_matches_arrival_time_without_the_clamp_biting() -> void:
	var coord := ArrowVolleyCoordinator.new()
	add_child_autofree(coord)
	var floor_s: float = coord.flight_time * ArrowVolleyCoordinator.MIN_FLIGHT_FRACTION
	assert_gt(RangedDamageFormula.FLIGHT_TIME, floor_s,
			"a shot's real airtime must clear the clamp floor, or arrows land early")

	# Nearest shot (launch 0.0) and furthest (launch TOTAL_STAGGER): both fly
	# exactly FLIGHT_TIME, so arrival order == firing order == distance order.
	for arrival in [RangedDamageFormula.FLIGHT_TIME,
			RangedDamageFormula.TOTAL_STAGGER + RangedDamageFormula.FLIGHT_TIME]:
		var hit := _hit(arrival)
		var launch_delay: float = maxf(hit.arrival_time - coord.shot_flight_time, 0.0)
		assert_almost_eq(coord._flight_for(hit, launch_delay),
				RangedDamageFormula.FLIGHT_TIME, 0.0001,
				"arrow airtime must equal the authored flight time at arrival %.2f" % arrival)
		assert_almost_eq(launch_delay + coord._flight_for(hit, launch_delay),
				hit.arrival_time, 0.0001,
				"the arrow must touch down exactly when its damage lands")
