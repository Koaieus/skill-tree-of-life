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


## A landing whose net `min_damage_taken` went negative is reclassified to
## [constant HitInstance.Kind.HEAL] by [method NodeCombat.take_damage] — the
## intended bunker/Bulwark tanking path, not an underflow. The coordinator
## must still draw its arrow.
func _heal_flipped_hit(structural_key: float) -> DamageInstance:
	var hit := _hit(structural_key)
	hit.kind = HitInstance.Kind.HEAL
	return hit


## Regression: the whole volley flipped to heals and NOTHING was drawn.
## `play()` filtered through `AttackOutcome.damage_hits()`, which keeps only
## `Kind.DAMAGE`, so the array came back empty and it returned before spawning
## a single Projectile — while `_commit` had already deducted the AP. Owner
## call 2026-09-04: "render. every. arrow. damage? render. 0? render. heal?
## render." See docs/domain/attack-timeline.md.
func test_heal_flipped_volley_still_draws_every_arrow() -> void:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_heal_flipped_hit(0.02))
	outcome.hits.append(_heal_flipped_hit(0.04))
	var coord := _mount_coord()
	coord.play(outcome)
	var projectiles := coord.get_children().filter(func(c): return c is Projectile)
	assert_eq(projectiles.size(), 2,
			"a volley that mitigated below zero still fires every arrow")
	await coord.play(outcome)


## The mixed case, which is what a crit inside a heal-flipped volley produces:
## one arrow cleared the armour, the rest flipped. Every one of them draws —
## the surviving damage hit must not be the only thing the player sees leave
## the bow.
func test_mixed_damage_and_heal_volley_draws_both() -> void:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_heal_flipped_hit(0.02))
	outcome.hits.append(_hit(0.04))
	var coord := _mount_coord()
	coord.play(outcome)
	var projectiles := coord.get_children().filter(func(c): return c is Projectile)
	assert_eq(projectiles.size(), 2, "one arrow per landing, whatever it did")
	await coord.play(outcome)


## A genuine [HealInstance] (not a flipped DamageInstance) is what
## [method AttackRecord.rebuild] constructs for a recorded `Kind.HEAL` — and
## the record round trip is on the SINGLE-PLAYER path too
## (`battle_system.gd`'s `_replay_launch`). So the coordinator must survive a
## hit that is not a DamageInstance at all: it used to type its loop variable
## `DamageInstance`, which would fail the cast at runtime while `mise run
## check` stayed green.
func test_rebuilt_heal_instance_does_not_break_the_loop() -> void:
	var heal := HealInstance.new()
	heal.origin = _origin
	heal.target = _target
	heal.amount = 5.0
	heal.effective_amount = 5.0
	heal.structural_key = 0.02
	var outcome := AttackOutcome.new()
	outcome.hits.append(heal)
	var coord := _mount_coord()
	coord.play(outcome)
	var projectiles := coord.get_children().filter(func(c): return c is Projectile)
	assert_eq(projectiles.size(), 1, "a HealInstance landing still draws an arrow")
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


## #950: every arrow used to land dead-centre on the target — visually a
## single THWACK painted N times. Landing points now spread across the
## target's disc, seeded from `outcome.resolve_seed` + hit index so a mirror
## replaying the same `AttackRecord` draws the identical picture (never the
## gameplay RNG, per `docs/domain/multiplayer-sync-model.md`). The offset is
## presentation only — flight target moves, the hit/damage/land beat do not.
func _collect_target_offsets(coord: ArrowVolleyCoordinator) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	for c in coord.get_children():
		if c is Projectile:
			offsets.append(c._target_pos - _target.global_position)
	return offsets


func test_landing_offsets_are_deterministic_across_replays() -> void:
	var outcome := AttackOutcome.new()
	outcome.resolve_seed = 42
	outcome.hits.append(_hit(0.02))
	outcome.hits.append(_hit(0.04))

	var coord_a := _mount_coord()
	coord_a.play(outcome)
	var offsets_a := _collect_target_offsets(coord_a)
	await coord_a.play(outcome)

	var coord_b := _mount_coord()
	coord_b.play(outcome)
	var offsets_b := _collect_target_offsets(coord_b)
	await coord_b.play(outcome)

	assert_eq(offsets_a.size(), 2, "one offset per hit")
	assert_eq(offsets_b.size(), 2, "one offset per hit")
	for i in offsets_a.size():
		assert_almost_eq(offsets_a[i].x, offsets_b[i].x, 0.0001,
				"same outcome replayed must land the same arrow %d at the same spot" % i)
		assert_almost_eq(offsets_a[i].y, offsets_b[i].y, 0.0001,
				"same outcome replayed must land the same arrow %d at the same spot" % i)


func test_landing_offsets_differ_by_hit_index() -> void:
	var outcome := AttackOutcome.new()
	outcome.resolve_seed = 7
	outcome.hits.append(_hit(0.02))
	outcome.hits.append(_hit(0.04))

	var coord := _mount_coord()
	coord.play(outcome)
	var offsets := _collect_target_offsets(coord)
	await coord.play(outcome)

	assert_eq(offsets.size(), 2)
	assert_true(offsets[0].distance_to(offsets[1]) > 0.01,
			"two different hit indices in the same outcome must draw different offsets")


func test_landing_offsets_stay_within_the_target_disc() -> void:
	var outcome := AttackOutcome.new()
	outcome.resolve_seed = 99
	for i in 20:
		outcome.hits.append(_hit(0.01 * float(i)))

	var coord := _mount_coord()
	coord.play(outcome)
	var offsets := _collect_target_offsets(coord)
	await coord.play(outcome)

	var r_max: float = 0.9 * _target.radius
	assert_eq(offsets.size(), 20)
	for offset in offsets:
		assert_true(offset.length() <= r_max + 0.01,
				"landing offset %s exceeds 0.9 * radius (%.2f)" % [offset, r_max])


## #495: a typed arrow's status rides as a second hit for the SAME landing,
## sharing the arrow's origin and target. It is not an arrow — one projectile
## per arrow, skipped by CLASS (a status never was an arrow), never by `kind`
## (a heal-flipped arrow still is one; see the two tests above).
func test_a_typed_arrows_status_hit_draws_no_second_arrow() -> void:
	var coord := _mount_coord()
	var outcome := AttackOutcome.new()
	var arrow := _hit(0.02)
	var status := RangedDamageFormula.RangedStatusInstance.new()
	status.origin = _origin
	status.target = _target
	status.structural_key = 0.02
	outcome.hits.append(arrow)
	outcome.hits.append(status)
	coord.play(outcome)
	var projectiles := coord.get_children().filter(func(c): return c is Projectile)
	assert_eq(projectiles.size(), 1, "one arrow, one projectile — the status half is not a second arrow")
	await coord.play(outcome)


# -- the wind-up (#1042, acceptance 2) ----------------------------------------


var _leaf_b: SkillNode


## The shipped scene, so `%FocusMarker` exists; visual timing shortened like
## [method _mount_coord].
func _mount_scene_coord() -> ArrowVolleyCoordinator:
	var coord: ArrowVolleyCoordinator = _COORD_SCENE.instantiate()
	coord.flight_time = 0.02
	coord.visual_scene = null
	add_child_autofree(coord)
	return coord


func _windup_tempo() -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.volley_draw_time = 0.5
	tempo.volley_place_stagger = 0.0
	tempo.volley_stagger_span = 0.03
	tempo.volley_flight_time = 0.02
	return tempo


## Three arrows from two leaves, RAMP cadence; the middle one from a second
## leaf so the inner-disk assert is per leaf, not "near the origin".
func _volley_outcome() -> AttackOutcome:
	_leaf_b = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_leaf_b.position = Vector2(0, 300)
	_graph.add_skill_node(_leaf_b)
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.RAMP
	for i in 3:
		var hit := _hit(float(i) * 0.5, 4.0)
		if i == 1:
			hit.origin = _leaf_b
		outcome.hits.append(hit)
	return outcome


func _projectiles(coord: Node) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in coord.get_children():
		if child is Projectile:
			out.append(child)
	return out


func test_windup_parks_every_arrow_inside_its_leaf_and_play_launches_those_instances() -> void:
	var coord := _mount_scene_coord()
	var outcome := _volley_outcome()
	coord.outcome = outcome
	var placed: Array = []
	var released: Array = []
	var on_placed := func(i: int, n: int) -> void: placed.append([i, n])
	var on_released := func(i: int, n: int) -> void: released.append([i, n])
	Events.volley_arrow_placed.connect(on_placed)
	Events.volley_arrow_released.connect(on_released)

	var staged := coord.begin_windup(RangedAttackPlan.new(), _windup_tempo())
	assert_almost_eq(staged, 0.5, 0.0001, "the wind-up is the draw time")
	var parked := _projectiles(coord)
	assert_eq(parked.size(), 3, "one parked projectile per arrow hit")
	for proj in parked:
		assert_false(proj.is_in_flight(), "parked, not launched")
	for i in parked.size():
		var leaf: SkillNode = outcome.hits[i].origin
		assert_lte(parked[i].global_position.distance_to(leaf.global_position), leaf.radius,
				"arrow %d sits inside its leaf's disc" % i)
	var marker := coord.focus_marker()
	assert_not_null(marker, "the coordinator's marker is its %FocusMarker")
	assert_almost_eq(marker.global_position, Vector2(0, 100), Vector2(0.01, 0.01),
			"during the wind-up the marker is the firing centroid")
	await wait_frames(3)
	assert_eq(placed, [[0, 3], [1, 3], [2, 3]], "placed once per arrow, in placement order")

	var ids: Array[int] = []
	for proj in parked:
		ids.append(proj.get_instance_id())
	var landings: Array = []
	coord.wave_landing.connect(func(points: PackedVector2Array) -> void: landings.append(points))
	coord.play(outcome)
	var launched := _projectiles(coord)
	assert_eq(launched.size(), 3, "play spawns nothing new")
	for i in launched.size():
		assert_eq(launched[i].get_instance_id(), ids[i], "…it launches the parked instance")
	assert_eq(landings.size(), 1, "wave_landing fires once at release")
	assert_eq(landings[0].size(), 3, "…with every arrow's landing point")
	for p in landings[0]:
		assert_lte(p.distance_to(_target.global_position), _target.radius, "…on the target's disc")
	await wait_until(func() -> bool: return _projectiles(coord).is_empty(), 3.0)
	assert_eq(released, [[0, 3], [1, 3], [2, 3]], "released once per arrow, in launch_at order")
	Events.volley_arrow_placed.disconnect(on_placed)
	Events.volley_arrow_released.disconnect(on_released)


func test_a_zero_draw_time_stages_nothing_and_play_spawns_as_today() -> void:
	var coord := _mount_scene_coord()
	var outcome := _volley_outcome()
	coord.outcome = outcome
	var tempo := _windup_tempo()
	tempo.volley_draw_time = 0.0
	assert_eq(coord.begin_windup(RangedAttackPlan.new(), tempo), 0.0)
	assert_eq(_projectiles(coord).size(), 0, "the escape hatch parks nothing")
	coord.play(outcome)
	assert_eq(_projectiles(coord).size(), 3, "play spawns and launches as before")
	await wait_until(func() -> bool: return _projectiles(coord).is_empty(), 3.0)


func test_focus_weight_is_the_arrows_summed_amount() -> void:
	var coord := _mount_scene_coord()
	var outcome := _volley_outcome()
	coord.outcome = outcome
	coord.begin_windup(RangedAttackPlan.new(), _windup_tempo())
	coord.play(outcome)
	for proj in _projectiles(coord):
		assert_almost_eq(proj.focus_weight, 4.0, 0.0001, "Σ|amount| of the arrow's hits")
	await wait_until(func() -> bool: return _projectiles(coord).is_empty(), 3.0)
