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
## The scene AttackVFX actually instantiates — the only version of this
## coordinator whose exports are the shipped ones.
const _COORD_SCENE := preload("res://ui/vfx/coordinator/arrow_volley_coordinator.tscn")

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


## docs/domain/attack-timeline.md flags `_flight_for` as the drift class
## #479/#481 cost five rounds of latches, and #504 RAISES the stakes: the
## arrow's flight is now the only thing keeping the visual in step with a
## mutation that happens at `arrival_time`. Miss, and the arrow lands out of
## sync with its own damage number — visibly.
##
## [b]This instantiates the SCENE, not `ArrowVolleyCoordinator.new()`.[/b] The
## exports are what drift, and exports are serialized per-scene: the old
## version of this test built the coordinator in code, read the code default
## for `flight_time` (0.45) instead of the scene's authored 2.0, and so
## certified a floor of 0.18s while the game ran one of 0.8s — green here
## while every shipped arrow landed 0.45s after its own damage. A test that
## constructs its subject cannot see a mistuned `.tscn`.
func test_every_arrow_touches_down_exactly_when_its_damage_lands() -> void:
	var coord := _COORD_SCENE.instantiate() as ArrowVolleyCoordinator
	add_child_autofree(coord)
	assert_almost_eq(coord.shot_flight_time, RangedDamageFormula.FLIGHT_TIME, 0.0001,
			"the scene must not override shot_flight_time away from the domain constant")

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
