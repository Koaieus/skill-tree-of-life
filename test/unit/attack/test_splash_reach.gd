extends GutTest

## A [SplashEffect] gathers with the targeting vocabulary: its
## [member SplashEffect.range_finder] answers geometry, its
## [member SplashEffect.ownership_filter] answers relation, and every copy it
## emits re-checks that same mask at land.

const _BLINDNESS_DEF := preload("res://effects/status/blindness.tres")

var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self)
	# Hostile nodes with no edge to the target, near and far: a hop-shaped
	# reach would never see them.
	_f.add_node(&"loose_near", Vector2(450, -120), _f.hostile)
	_f.add_node(&"loose_far", Vector2(1100, 0), _f.hostile)
	await get_tree().process_frame


func _splash(filter: int, finder: RangeFinder) -> SplashEffect:
	var inner := ApplyStatusEffect.new()
	inner.def = _BLINDNESS_DEF
	inner.power = 1.0
	var splash := SplashEffect.new()
	splash.inner = inner
	splash.ownership_filter = filter
	splash.range_finder = finder
	return splash


func _euclid(r: float) -> EuclideanRangeFinder:
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = r
	return finder


func _landing() -> HitLanding:
	var landing := HitLanding.new()
	landing.attacker = _f.attacker
	landing.origin = _f.leaves[0]
	landing.read_node = _f.leaves[0]
	landing.target = _f.target
	return landing


## Every node the splash's copies landed on, the target excluded.
func _splashed(splash: SplashEffect) -> Dictionary[SkillNode, HitInstance]:
	var landing := _landing()
	splash.apply(landing)
	var out: Dictionary[SkillNode, HitInstance] = {}
	for hit in landing.hits:
		if hit.target != _f.target:
			out[hit.target] = hit
	return out


func test_a_euclidean_splash_reaches_every_hostile_node_whose_hitbox_touches_the_circle() -> void:
	var hostile_nodes: Array[SkillNode] = []
	for n: SkillNode in _f.nodes.values():
		if n != _f.target and n.owned_by == _f.hostile:
			hostile_nodes.append(n)
	assert_eq(hostile_nodes.size(), 4, "cluster + two loose hostile nodes")
	var r := 0.0
	var seen_some := false
	var seen_all := false
	while r <= 800.0:
		var got := _splashed(_splash(SkillNode.Ownership.HOSTILE, _euclid(r)))
		var expected: Array[SkillNode] = []
		for n in hostile_nodes:
			if _f.target.global_position.distance_to(n.global_position) - n.radius <= r:
				expected.append(n)
		assert_eq(got.size(), expected.size(), "r=%s: as many splashes as hostile nodes in reach" % r)
		for n in expected:
			assert_true(got.has(n), "r=%s reaches %s" % [r, n.name])
		seen_some = seen_some or (not expected.is_empty() and expected.size() < hostile_nodes.size())
		seen_all = seen_all or expected.size() == hostile_nodes.size()
		r += 25.0
	assert_true(seen_some, "the sweep crosses a partial reach")
	assert_true(seen_all, "the sweep reaches every hostile node")


func test_an_any_filter_reaches_the_attackers_own_node_and_hostile_skips_it() -> void:
	var leaf := _f.leaves[0]
	var any := _splashed(_splash(15, _euclid(100.0)))
	assert_true(any.has(leaf), "Any: the attacker's own leaf in range is splashed")
	var hostile := _splashed(_splash(SkillNode.Ownership.HOSTILE, _euclid(100.0)))
	assert_false(hostile.has(leaf), "Hostile: never the attacker's own node")
	assert_eq((any[leaf] if any.has(leaf) else HitInstance.new()).land_mask, 15,
			"a copy carries the splash's own mask")


func test_a_hostile_node_that_flips_owner_before_land_lands_gated() -> void:
	var splashed := _splashed(_splash(SkillNode.Ownership.HOSTILE, _euclid(200.0)))
	var flipper: SkillNode = _f.nodes[&"hostile_a"]
	assert_true(splashed.has(flipper), "hostile_a is in reach")
	if not splashed.has(flipper):
		return
	_f.alloc.force_allocate(_f.attacker, flipper)
	var status := splashed[flipper] as StatusInstance
	status.land_on(flipper.get_combat(), CombatWorld.live())
	assert_true(status.gated, "no longer hostile at land: a dud")
	assert_eq(status.power, 0.0)
