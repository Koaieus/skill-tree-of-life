extends GutTest

## `--lethal`: the e2e run's entities each survive at most ~3 node losses, so a
## two-AI game reaches a verdict inside the harness's default wall clock. The
## owner's bound (2026-09-30): SET node_health 1, health 3, dealloc_damage 1,
## core_healing 0 — asserted here as literals on purpose, so a re-tune of the
## harness's numbers has to be made twice.

const _ENTITY_SCENE := preload("res://entity/entity.tscn")


func _spawn() -> Entity:
	var e: Entity = _ENTITY_SCENE.instantiate()
	add_child_autofree(e)
	return e


func _assert_lethal(e: Entity) -> void:
	var board := e.stat_board
	assert_eq(float(board.get_value(&"health")), 3.0, "health cap is SET to 3")
	assert_eq((board.health as PoolStat).current, 3.0, "health current clamps down to the cap")
	assert_eq(float(board.get_value(&"node_health")), 1.0, "node_health is SET to 1")
	assert_eq(float(board.get_value(&"dealloc_damage")), 1.0, "dealloc_damage is SET to 1")
	assert_eq(float(board.get_value(&"core_healing")), 0.0, "core_healing is SET to 0")


func test_make_lethal_sets_the_four_stats() -> void:
	var e := _spawn()
	MpHarness.make_lethal(e)
	_assert_lethal(e)


func test_an_armed_harness_makes_every_later_entity_lethal() -> void:
	var harness := MpHarness.new()
	add_child_autofree(harness)
	harness.arm_lethal()
	var e := _spawn()
	_assert_lethal(e)


func test_the_sets_survive_a_board_round_trip_without_doubling() -> void:
	var host := _spawn()
	MpHarness.make_lethal(host)
	var mirror := _spawn()
	MpHarness.make_lethal(mirror)
	mirror.stat_board.read_dict(host.stat_board.to_dict())
	_assert_lethal(mirror)
	assert_eq(mirror.stat_board.to_dict(), host.stat_board.to_dict(),
			"a mirror that applied the flag itself holds the host's board exactly")


func test_an_ordinary_launch_is_not_lethal() -> void:
	assert_false(HarnessFlags.has(HarnessFlags.LETHAL, PackedStringArray(["--autoplay"])))
	assert_true(HarnessFlags.has(HarnessFlags.LETHAL, PackedStringArray(["--lethal"])))
