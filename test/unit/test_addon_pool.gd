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
	var e := _entry(_SPIKE_RING, {&"damage": 7.0, &"spike_count": 16})
	var addon := e.mint(_rng()) as SpikeRingAddon
	assert_not_null(addon)
	assert_eq(addon.damage, 7.0)
	assert_eq(addon.spike_count, 16)
	addon.queue_free()


func test_mint_with_null_scene_returns_null() -> void:
	var e := AddonPoolEntry.new()
	e.addon_scene = null
	assert_null(e.mint(_rng()))


func test_pool_pick_respects_budget() -> void:
	var pool := AddonPool.new()
	pool.entries = [_entry(_SPIKE_RING, {}, 5, 10.0)]  # cost 5
	# Budget 3 → nothing affordable.
	var picked := GraphProcgen._weighted_pick_addon(pool, 3, _rng())
	assert_null(picked)
	# Budget 5 → entry affordable.
	var picked2 := GraphProcgen._weighted_pick_addon(pool, 5, _rng())
	assert_not_null(picked2)


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
		var p := GraphProcgen._weighted_pick_addon(pool, 1, rng)
		if p != null and p.id == &"high":
			high_count += 1
	assert_gt(high_count, 90, "99:1 weight should favour 'high' overwhelmingly")
