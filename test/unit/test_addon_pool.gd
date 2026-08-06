extends GutTest

## AddonPoolEntry.mint() + AddonPool weighted pick.

const _SPIKE_RING := preload("res://skill_node/addons/spike_ring_addon.tscn")


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _entry(scene: PackedScene, params: Dictionary = {}, cost: int = 1, weight: float = 1.0) -> AddonPoolEntry:
	var e := AddonPoolEntry.new()
	e.id = &"spike_ring"
	e.addon_scene = scene
	e.params = params
	e.cost = cost
	e.weight = weight
	return e


func test_mint_returns_addon_instance() -> void:
	var e := _entry(_SPIKE_RING)
	var addon := e.mint(_rng())
	assert_not_null(addon)
	assert_true(addon is SkillNodeAddon, "minted instance must be SkillNodeAddon")
	addon.queue_free()


func test_mint_applies_params() -> void:
	var e := _entry(_SPIKE_RING, {&"spike_count": 16, &"spike_overshoot": 0.6})
	var addon := e.mint(_rng()) as SpikeRingAddon
	assert_not_null(addon)
	assert_eq(addon.spike_count, 16)
	assert_almost_eq(addon.spike_overshoot, 0.6, 0.001)
	addon.queue_free()


func test_mint_with_null_scene_returns_null() -> void:
	var e := AddonPoolEntry.new()
	e.addon_scene = null
	assert_null(e.mint(_rng()))


func test_pool_pick_empty_returns_null() -> void:
	var pool := AddonPool.new()
	pool.entries = []
	var picked := GraphProcgen._weighted_pick_addon(pool, [], _rng())
	assert_null(picked)


func test_pool_pick_weighted() -> void:
	var pool := AddonPool.new()
	var a := _entry(_SPIKE_RING, {}, 1, 99.0)
	a.id = &"high"
	var b := _entry(_SPIKE_RING, {}, 1, 1.0)
	b.id = &"low"
	pool.entries = [a, b]
	var high_count := 0
	for i in 100:
		var rng := _rng(i + 1)
		var p := GraphProcgen._weighted_pick_addon(pool, [], rng)
		if p != null and p.id == &"high":
			high_count += 1
	assert_gt(high_count, 90, "99:1 weight should favour 'high' overwhelmingly")


func test_pool_pick_excludes_already_minted_unique_scenes() -> void:
	# Same scene listed twice; once "minted" → pick falls through to fallback.
	var pool := AddonPool.new()
	var a := _entry(_SPIKE_RING, {}, 1, 1.0)
	a.id = &"spike"
	pool.entries = [a]
	# Mark scene as already minted → no candidates → null.
	var picked := GraphProcgen._weighted_pick_addon(pool, [_SPIKE_RING], _rng())
	assert_null(picked)


func test_slot_count_distribution_sampling() -> void:
	var policy := AddonPolicy.new()
	policy.slot_count_weights = {0: 60.0, 1: 25.0, 2: 12.0, 3: 3.0}
	# Sample many; assert distribution is roughly right.
	var counts := [0, 0, 0, 0]
	for i in 1000:
		var rng := _rng(i + 1)
		var n := policy.sample_slot_count(rng)
		if n >= 0 and n <= 3:
			counts[n] += 1
	# Loose bounds: 50%–70% zero, 15%–35% one. Stochastic but stable.
	assert_true(counts[0] >= 500 and counts[0] <= 700, "0-slot count = %d not in [500,700]" % counts[0])
	assert_true(counts[1] >= 150 and counts[1] <= 350, "1-slot count = %d not in [150,350]" % counts[1])
