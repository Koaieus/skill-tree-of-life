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
	# `flight_time` isn't where the real wait was: `_flight_for` reads each
	# shot's actual airtime off its ScheduleEntry (a few ms here), so what
	# dominated was Projectile's post-arrival wait on LightArrow's `finished`
	# signal — LightArrow's own `hold_seconds` (0.35) + `fade_seconds` (0.4),
	# a purely cosmetic dwell nothing here asserts on. `visual_scene = null`
	# skips instantiating a visual at all (Projectile._instantiate_visual's
	# own null guard), which drops `_wait_for_visual_done` to Projectile's
	# `linger_seconds` fallback (0.1) instead — this is the same
	# "swap a lighter double" pattern as the AIController.turn_delay override
	# in 8917a81, expressed through an export already meant for exactly this.
	coord.visual_scene = null
	add_child_autofree(coord)
	return coord


## #543: a hit records its STRUCTURAL key, never seconds. These outcomes are
## hand-built and so carry the default [constant ScheduleEntry.Cadence.LITERAL],
## where the key IS the second — which is exactly what these drain tests want
## and what `arrival_time` used to mean here.
func _hit(structural_key: float, amount: float = 5.0) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.origin = _origin
	hit.target = _target
	hit.amount = amount
	hit.effective_amount = amount
	hit.structural_key = structural_key
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
## arrow's flight is the only thing keeping the visual in step with a mutation
## that happens at the schedule's `arrive_at`. Miss, and the arrow lands out of
## sync with its own damage number — visibly.
##
## [b]#543 removed the drift class rather than re-testing it.[/b] The old
## version subtracted a `shot_flight_time` export from `arrival_time` to
## recover a launch delay, and a mistuned export desynced every arrow. The
## compiler now assigns BOTH ends of the window, so the identity below is
## structural, not arithmetic — there is no second number left to keep equal.
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
	assert_null(coord.tempo,
			"the scene must not override the shared default tempo")

	# A real RAMP outcome: nearest leaf (key 0.0) and furthest (key 1.0).
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.RAMP
	outcome.hits.append(_hit(0.0))
	outcome.hits.append(_hit(1.0))
	var schedule := OutcomeSchedule.compile(outcome, null, 1.0)
	var tempo := PresentationTempo.shared_default()

	for entry in schedule.entries:
		assert_almost_eq(coord._flight_for(entry), tempo.volley_flight_time, 0.0001,
				"arrow airtime must equal the authored flight time at key %.2f"
						% entry.structural_key)
		assert_almost_eq(entry.launch_at + coord._flight_for(entry),
				entry.arrive_at, 0.0001,
				"the arrow must touch down exactly when its damage lands")

	# The domain constants RangedDamageFormula still publishes and the tempo
	# the compiler now reads must agree, or the ramp silently retempos.
	assert_almost_eq(tempo.volley_flight_time, RangedDamageFormula.FLIGHT_TIME, 0.0001,
			"default tempo's flight time must match the domain constant")
	assert_almost_eq(tempo.volley_stagger_span, RangedDamageFormula.TOTAL_STAGGER, 0.0001,
			"default tempo's stagger span must match the domain constant")
	assert_almost_eq(tempo.volley_draw_time, RangedDamageFormula.DRAW_TIME, 0.0001,
			"default tempo's draw time must match the domain constant")
