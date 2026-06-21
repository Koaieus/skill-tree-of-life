extends GutTest

## ArchetypeBalancer: under-represented archetypes get higher effective
## weight; over-represented get depressed.


func _archetype(id: StringName, ratio: float) -> ArchetypePolicy:
	var a := ArchetypePolicy.new()
	a.id = id
	a.target_ratio = ratio
	return a


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_disabled_does_not_run() -> void:
	# The balancer's `enabled` is read at the call site; the resource itself
	# just exposes the picking function. Sanity-check that calling pick()
	# directly still produces a valid index even with enabled = false.
	var b := ArchetypeBalancer.new()
	b.enabled = false
	b.strength_epsilon = 0.1
	var arch: Array[ArchetypePolicy] = [_archetype(&"a", 0.5), _archetype(&"b", 0.5)]
	var counts := PackedInt32Array([0, 0])
	var idx := b.pick(arch, counts, 0, _rng())
	assert_true(idx == 0 or idx == 1)


func test_under_represented_archetype_is_preferred() -> void:
	var b := ArchetypeBalancer.new()
	b.strength_epsilon = 0.01  # strict
	var arch: Array[ArchetypePolicy] = [_archetype(&"a", 0.5), _archetype(&"b", 0.5)]
	# Heavily over-assigned to a; under-assigned to b.
	var counts := PackedInt32Array([18, 2])
	var hits_b := 0
	for i in 100:
		var idx := b.pick(arch, counts, 20, _rng(i + 1))
		if idx == 1:
			hits_b += 1
	assert_gt(hits_b, 95, "expected ≥95%% of picks to go to under-represented b; got %d" % hits_b)


func test_balanced_state_picks_roughly_evenly() -> void:
	var b := ArchetypeBalancer.new()
	b.strength_epsilon = 0.1
	var arch: Array[ArchetypePolicy] = [_archetype(&"a", 0.5), _archetype(&"b", 0.5)]
	var counts := PackedInt32Array([50, 50])
	var hits_a := 0
	for i in 200:
		var idx := b.pick(arch, counts, 100, _rng(i + 1))
		if idx == 0:
			hits_a += 1
	# At balanced state with equal targets + epsilon, expect ~50%.
	assert_true(hits_a > 70 and hits_a < 130, "expected ~100 hits_a; got %d" % hits_a)


func test_empty_archetypes_returns_negative_one() -> void:
	var b := ArchetypeBalancer.new()
	var idx := b.pick([], PackedInt32Array(), 0, _rng())
	assert_eq(idx, -1)
