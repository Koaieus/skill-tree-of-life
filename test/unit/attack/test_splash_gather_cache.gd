extends GutTest

## A volley's splash arrows share one gather cache: the finder sweeps once per
## (target, finder, reach), however many arrows land there, and the mask runs
## after the cached gather — so the cache changes how often the board is
## swept, never who a blast lands on.

const RAW := 10.0


## Counts its sweeps; otherwise the Euclidean finder unchanged.
class CountingFinder extends EuclideanRangeFinder:
	var sweeps := 0

	func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
		sweeps += 1
		return super.gather(source, mirror, attacker)


var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	for leaf in _f.leaves:
		VolleyBoardFixture.set_stat(leaf, &"ranged_damage", RAW)
	await get_tree().process_frame


func _blast(finder: CountingFinder) -> AmmoType:
	var splash := SplashEffect.new()
	splash.inner = PairedDamageEffect.new()
	splash.ownership_filter = SkillNode.Ownership.HOSTILE
	splash.range_finder = finder
	var ammo := AmmoType.new()
	ammo.id = &"test_blast"
	ammo.on_hit_effects = [splash]
	return ammo


func _finder(r: float) -> CountingFinder:
	var finder := CountingFinder.new()
	finder.max_distance = r
	return finder


## [param ammo] arrows, one per entry, cycling the leaves onto the target —
## every arrow's riders through [param cache]. Returns the riders, in order.
func _volley(ammo: Array[AmmoType], cache: Dictionary) -> Array[HitInstance]:
	var riders: Array[HitInstance] = []
	for i in ammo.size():
		var leaf := _f.leaves[i % _f.leaves.size()]
		var arrow := RangedDamageFormula.compute(_f.attacker, leaf, _f.target, ammo[i])
		riders.append_array(RangedDamageFormula.riders_for(arrow, cache))
	return riders


func _repeat(ammo: AmmoType, n: int) -> Array[AmmoType]:
	var out: Array[AmmoType] = []
	for _i in n:
		out.append(ammo)
	return out


func _targets(riders: Array[HitInstance]) -> Array:
	return riders.map(func(h: HitInstance) -> SkillNode: return h.target)


func test_ten_same_radius_arrows_on_one_target_sweep_once() -> void:
	var finder := _finder(200.0)
	_volley(_repeat(_blast(finder), 10), {})
	assert_eq(finder.sweeps, 1, "one (target, finder, reach): one sweep")


func test_five_and_five_at_two_radii_sweep_twice() -> void:
	var near := _finder(120.0)
	var far := _finder(300.0)
	var ammo := _repeat(_blast(near), 5)
	ammo.append_array(_repeat(_blast(far), 5))
	_volley(ammo, {})
	assert_eq(near.sweeps + far.sweeps, 2, "two radii: two sweeps")
	assert_eq(near.sweeps, 1)
	assert_eq(far.sweeps, 1)


func test_without_a_shared_cache_every_arrow_sweeps() -> void:
	var finder := _finder(200.0)
	var ammo := _blast(finder)
	for i in 4:
		var arrow := RangedDamageFormula.compute(_f.attacker, _f.leaves[0], _f.target, ammo)
		RangedDamageFormula.riders_for(arrow)
	assert_eq(finder.sweeps, 4, "a landing handed no cache sweeps every time")


func test_the_cache_changes_the_sweep_count_never_the_blast() -> void:
	var cached := _volley(_repeat(_blast(_finder(300.0)), 6), {})
	var fresh: Array[HitInstance] = []
	var ammo := _blast(_finder(300.0))
	for i in 6:
		fresh.append_array(_volley([ammo] as Array[AmmoType], {}))
	assert_gt(cached.size(), 6, "the blast reaches past the target")
	assert_eq(_targets(cached), _targets(fresh), "same nodes, same order, with or without the cache")
