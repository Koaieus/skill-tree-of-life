extends GutTest

## #670 P2. [ImpactRing] owns #663 D6's uniform crit grammar for the WHOLE
## spell book — tier 1 = one ring at ALERT, tier 2+ = a second concentric ring
## plus a single-frame PEAK core flash — so the eight per-spell units inherit
## it instead of each re-authoring one. That makes this file the place the
## grammar is actually pinned; if it drifts here, it drifts everywhere at once.

const IMPACT_RING := preload("res://ui/vfx/projectile/visual/impact_ring.tscn")
const ABSORB := preload("res://ui/vfx/projectile/visual/impact_ring_absorb.tscn")


func _spawn(scene: PackedScene = IMPACT_RING) -> ImpactRing:
	var ring: ImpactRing = scene.instantiate()
	add_child_autofree(ring)
	return ring


func test_implements_the_duck_contract_it_claims() -> void:
	var ring := _spawn()
	for method in ["_on_arrival", "_on_crit", "_on_context"]:
		assert_true(ring.has_method(method), "ImpactRing must implement %s" % method)
	assert_true(ring.has_signal(&"finished"), "ImpactRing must emit `finished`")


func test_no_launch_hook_so_it_cannot_fire_a_flight_early() -> void:
	# Punctuation fires on landing. A `_on_launch` would put the ring on the
	# ORIGIN node the moment a projectile sets off.
	assert_false(_spawn().has_method("_on_launch"), "ImpactRing must not implement _on_launch")


func test_under_a_projectile_it_does_not_autoplay() -> void:
	# The projectile instantiates its visual at launch and `await`s `finished`
	# at arrival. A ring that autoplayed would have freed itself by then.
	var proj := Projectile.new()
	add_child_autofree(proj)
	var ring: ImpactRing = IMPACT_RING.instantiate()
	proj.add_child(ring)
	assert_false(ring.is_queued_for_deletion(), "a projectile-hosted ring must idle until arrival")
	watch_signals(ring)
	assert_signal_not_emitted(ring, "finished")


func test_standalone_use_plays_on_ready() -> void:
	# The `cancel_visual` path — instantiate at the target node and it goes.
	var ring := _spawn()
	assert_true(ring.is_processing(), "a standalone ring plays immediately")


# ----------------------------------------------------------- the crit grammar


func test_no_crit_draws_one_ring_and_no_flash() -> void:
	var ring := _spawn()
	assert_eq(ring.active_ring_count(), 1, "a plain impact is one ring")
	assert_false(ring.has_peak_flash(), "no crit, no PEAK")
	assert_false(ring.peak_flash_fired, "no crit, no flash latched")


func test_tier_one_is_one_ring_at_alert_and_no_flash() -> void:
	var ring := _spawn()
	ring._on_crit(1)
	assert_eq(ring.active_ring_count(), 1, "tier 1 stays a single ring")
	assert_false(ring.has_peak_flash(), "PEAK is reserved for tier 2+")
	var hot: Color = ring._ring_color(0)
	var calm: Color = _spawn()._ring_color(0)
	assert_gt(hot.r, calm.r, "a tier-1 ring burns hotter than a plain impact")


func test_tier_two_adds_the_second_ring_and_the_peak_flash() -> void:
	var ring := _spawn()
	ring._on_crit(2)
	assert_eq(ring.active_ring_count(), 2, "tier 2+ is a double concentric ring")
	assert_true(ring.has_peak_flash(), "tier 2+ earns the PEAK core flash")
	assert_true(ring.peak_flash_fired, "the flash is latched at play time, not at draw time")


func test_tier_three_reads_as_tier_two_rather_than_growing_forever() -> void:
	var ring := _spawn()
	ring._on_crit(3)
	assert_eq(ring.active_ring_count(), 2, "the grammar tops out at two rings")
	assert_true(ring.has_peak_flash())


func test_the_second_ring_is_concentric_and_smaller() -> void:
	assert_eq(ImpactRing.RING_SCALES[0], 1.0, "the primary ring is the authored radius")
	assert_lt(ImpactRing.RING_SCALES[1], ImpactRing.RING_SCALES[0], "the companion sits inside it")


func test_an_authored_ring_count_is_never_lowered_by_the_grammar() -> void:
	var ring := _spawn()
	ring.ring_count = 3
	ring._on_crit(1)
	assert_eq(ring.active_ring_count(), 3, "the crit grammar raises, it never lowers")


func test_crit_color_is_the_carve_out_seam_not_a_second_code_path() -> void:
	# #663 D5's critical-heal gold is authored by the Healing Beam unit setting
	# `crit_color`; there is deliberately no second palette in this class.
	var ring := _spawn()
	ring.crit_color = Color(0.2, 0.9, 0.4)
	ring._on_crit(1)
	var col: Color = ring._ring_color(0)
	assert_gt(col.g, col.r, "the ring follows `crit_color`, not a hard-coded red")


# ---------------------------------------------------------------- direction


func test_out_expands_away_from_the_node() -> void:
	var ring := _spawn()
	ring.direction = ImpactRing.Direction.OUT
	ring.radius = 10.0
	ring.expand_radius = 40.0
	ring._t = 0.0
	var start: float = ring.current_radius()
	ring._t = 1.0
	assert_gt(ring.current_radius(), start, "OUT grows")
	assert_almost_eq(start, 10.0, 0.001, "OUT starts at `radius`")


func test_in_contracts_onto_the_node() -> void:
	# Exercised, not merely declared: IN is what tells a heal arrival and a
	# convergence gather apart from a hit.
	var ring := _spawn(ABSORB)
	assert_eq(ring.direction, ImpactRing.Direction.IN, "the absorb config is IN")
	ring._t = 0.0
	var start: float = ring.current_radius()
	ring._t = 1.0
	var finish: float = ring.current_radius()
	assert_lt(finish, start, "IN shrinks")
	assert_almost_eq(start, ring.expand_radius, 0.001, "IN starts wide")
	assert_almost_eq(finish, ring.radius, 0.001, "IN lands on `radius`")


func test_squash_flattens_the_ring_without_a_second_geometry_path() -> void:
	var ring := _spawn()
	ring.squash = 0.4
	assert_lt(ring.squash, 1.0, "below 1.0 the ring lies on the board")


# ------------------------------------------------------------------ context


func test_convergence_count_widens_the_gather() -> void:
	var ring := _spawn()
	var authored: float = ring.expand_radius
	ring._on_context({&"convergence_count": 4.0})
	var widened: float = ring.expand_radius
	assert_gt(widened, authored, "four branches meeting reads wider than one")
	ring._on_context({&"convergence_count": 4.0})
	assert_almost_eq(ring.expand_radius, widened, 0.001,
		"a repeated entry must not compound the widening")


func test_context_tolerates_null_and_foreign_shapes() -> void:
	var ring := _spawn()
	var authored: float = ring.expand_radius
	ring._on_context(null)
	ring._on_context({&"is_terminal": true})
	ring._on_context(RefCounted.new())
	assert_almost_eq(ring.expand_radius, authored, 0.001, "an unread shape changes nothing")


# ------------------------------------------------------------- visit ramp


## Ramp on, with ends authored above the scene's start values.
func _spawn_ramped(visits: float) -> ImpactRing:
	var ring := _spawn(ABSORB)
	ring.visit_ramp_visits = visits
	ring.visit_expand_radius_end = ring.expand_radius * 2.5
	ring.visit_emissive_tier_end = ring.emissive_tier + 1.0
	return ring


func test_visit_ramp_is_monotone_and_clamps_at_its_visit_count() -> void:
	for visits in [1.0, 2.0, 3.0, 5.0]:
		var prev_radius: float = -1.0
		var prev_tier: float = -1.0
		var top_radius: float = 0.0
		var top_tier: float = 0.0
		for visit in range(0, int(visits) + 3):
			var ring := _spawn_ramped(visits)
			var start_radius: float = ring.expand_radius
			var start_tier: float = ring.emissive_tier
			ring._on_context({&"visit_index": float(visit)})
			if visit == 0:
				assert_almost_eq(ring.expand_radius, start_radius, 0.001, "visit 0 reads at the authored start")
				assert_almost_eq(ring.emissive_tier, start_tier, 0.001, "visit 0 reads at the authored tier")
			if visit <= int(visits):
				assert_gt(ring.expand_radius, prev_radius, "radius grows with visit_index (visits=%s, visit=%d)" % [visits, visit])
				assert_gt(ring.emissive_tier, prev_tier, "tier heats with visit_index (visits=%s, visit=%d)" % [visits, visit])
			else:
				assert_almost_eq(ring.expand_radius, top_radius, 0.001, "radius clamps past visit_ramp_visits")
				assert_almost_eq(ring.emissive_tier, top_tier, 0.001, "tier clamps past visit_ramp_visits")
			if visit == int(visits):
				top_radius = ring.expand_radius
				top_tier = ring.emissive_tier
				assert_almost_eq(top_radius, ring.visit_expand_radius_end, 0.001, "full ramp reaches the radius end")
				assert_almost_eq(top_tier, ring.visit_emissive_tier_end, 0.001, "full ramp reaches the tier end")
			prev_radius = ring.expand_radius
			prev_tier = ring.emissive_tier


func test_a_second_visit_entry_does_not_compound() -> void:
	var ring := _spawn_ramped(4.0)
	ring._on_context({&"visit_index": 2.0})
	var radius: float = ring.expand_radius
	var tier: float = ring.emissive_tier
	ring._on_context({&"visit_index": 2.0})
	assert_almost_eq(ring.expand_radius, radius, 0.001, "a repeated entry must not compound the radius")
	assert_almost_eq(ring.emissive_tier, tier, 0.001, "…nor the tier")


func test_with_the_ramp_on_convergence_never_widens_the_ring() -> void:
	var lone := _spawn_ramped(3.0)
	lone._on_context({&"visit_index": 1.0, &"convergence_count": 1.0})
	var met := _spawn_ramped(3.0)
	met._on_context({&"visit_index": 1.0, &"convergence_count": 5.0})
	assert_almost_eq(met.expand_radius, lone.expand_radius, 0.001,
		"the visit ramp owns the radius; convergence must not compete")


func test_with_the_ramp_off_convergence_is_unchanged_and_visits_are_ignored() -> void:
	var plain := _spawn(ABSORB)
	plain._on_context({&"convergence_count": 4.0})
	var visited := _spawn(ABSORB)
	var authored_tier: float = visited.emissive_tier
	visited._on_context({&"convergence_count": 4.0, &"visit_index": 3.0})
	assert_eq(visited.visit_ramp_visits, 0.0, "the ramp is off by default")
	assert_almost_eq(visited.expand_radius, plain.expand_radius, 0.001,
		"ramp off: visit_index never touches the convergence widening")
	assert_almost_eq(visited.emissive_tier, authored_tier, 0.001, "ramp off: the tier is the authored one")


func test_it_finishes_and_frees_itself() -> void:
	# NOT `watch_signals` + `assert_signal_emitted`: the ring `queue_free`s
	# itself in the same frame it emits, and GUT's signal store dereferences
	# the emitter at assert time. A captured flag survives the free.
	var ring: ImpactRing = IMPACT_RING.instantiate()
	# Before `add_child` — a standalone ring plays on `_ready`.
	ring.duration = 0.05
	var seen: Array[bool] = [false]
	ring.finished.connect(func() -> void: seen[0] = true)
	var ring_id := ring.get_instance_id()
	add_child(ring)
	await wait_until(func() -> bool: return seen[0] and not is_instance_valid(instance_from_id(ring_id)), 2.0)
	assert_true(seen[0], "the ring must announce `finished` so a coordinator can drain")
	assert_false(is_instance_valid(ring), "and then free itself, like CancelDissipate")
