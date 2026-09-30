extends GutTest

## A StatPool's resource_name names its contents minus the value AND the side
## the pool's rolls land on for whoever holds them: unmarked when every roll
## is a boon, else suffixed `[bane]` / `[mixed]` / `[volatile]`. Judged by the def
## (a positive roll on a `lower_is_better` stat is a bane), and correct after
## a `.tres` load whatever field order the setters fire in.

const _POOL_DIR := "res://procgen/pools/"


func _pool(stat: StringName, op: StatModifier.Operation, unit: float) -> StatPool:
	# Declaration order — the order `.tres` deserialization assigns fields in.
	var p := StatPool.new()
	p.stat_id = stat
	p.operation = op
	p.unit_value = unit
	return p


func test_boon_pool_is_unmarked() -> void:
	assert_eq(_pool(&"dexterity", StatModifier.Operation.INCREASE, 7.0).resource_name, "dexterity +%")


func test_negative_pool_is_bane_and_signed() -> void:
	assert_eq(_pool(&"armor", StatModifier.Operation.INCREASE, -3.0).resource_name, "armor -% [bane]")


func test_positive_pool_on_lower_is_better_stat_is_bane() -> void:
	assert_eq(_pool(&"dealloc_damage", StatModifier.Operation.ADD_BASE, 2.0).resource_name,
			"dealloc_damage + [bane]")


func test_range_crossing_neutral_is_mixed() -> void:
	var p := _pool(&"dexterity", StatModifier.Operation.ADD_BASE, 3.0)
	p.range_floor = -1.0
	assert_eq(p.resource_name, "dexterity + [mixed]")


func test_sign_flipping_multiply_is_volatile() -> void:
	var p := _pool(&"dexterity", StatModifier.Operation.MULTIPLY, -0.2)
	assert_eq(p.resource_name, "dexterity × [volatile]")


func test_max_tier_cap_recomputes_name() -> void:
	var p := _pool(&"dexterity", StatModifier.Operation.MULTIPLY, -0.2)
	p.max_tier = 1
	assert_eq(p.resource_name, "dexterity × [bane]")


## Every authored pool's STORED name matches what its fields say — a stale
## name in a `.tres` (the setters fixed on load, never resaved) fails here.
func test_every_authored_pool_stores_its_computed_name() -> void:
	var checked := 0
	for f in DirAccess.get_files_at(_POOL_DIR):
		if not f.ends_with(".tres"):
			continue
		var path := _POOL_DIR + f
		var pack := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as StatPack
		if pack == null:
			continue
		var text := FileAccess.get_file_as_string(path)
		for p: StatPool in pack.pools:
			checked += 1
			assert_true(text.contains('resource_name = "%s"' % p.resource_name),
					"%s stores a stale name for '%s'" % [f, p.resource_name])
	assert_gt(checked, 0, "found authored pools to check")
