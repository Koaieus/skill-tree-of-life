extends GutTest

## [method GraphProcgenConfig.private_copy] is THE way to take a preset you
## intend to write to. A plain `duplicate(true)` stops at every ExtResource
## boundary, and all five modules are top-level `.tres` files, so a write
## through such a copy lands on the cached module every other loader of the
## preset in this process shares — the order-dependent flake #1731 chased.

const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"
const _MODULES: Array[StringName] = [&"topology", &"shape", &"starting", &"content", &"blockers"]


func test_every_module_is_a_private_instance() -> void:
	var src: GraphProcgenConfig = load(_PRESET_PATH)
	var copy := src.private_copy()
	assert_ne(copy, src, "the config itself is a copy")
	for m in _MODULES:
		assert_not_null(copy.get(m), "%s survives the copy" % m)
		assert_ne(copy.get(m), src.get(m), "%s is a private instance, never the cached module" % m)


func test_a_write_through_the_copy_never_reaches_the_cached_preset() -> void:
	var src: GraphProcgenConfig = load(_PRESET_PATH)
	var authored_count := src.topology.node_count
	var authored_placements := src.content.guaranteed_placements.size()
	var authored_blockers := src.blockers.blocker_per_small

	var copy := src.private_copy()
	copy.topology.node_count = authored_count + 1
	copy.content.guaranteed_placements = [] as Array[Resource]
	copy.blockers.blocker_per_small = authored_blockers + 1
	copy.camp_sizes = [1, 2]
	copy.seed = 7

	assert_eq(src.topology.node_count, authored_count, "node_count is untouched on the cached module")
	assert_eq(src.content.guaranteed_placements.size(), authored_placements, "placements untouched")
	assert_eq(src.blockers.blocker_per_small, authored_blockers, "blocker density untouched")
	assert_eq(src.camp_sizes.size(), 0, "the runtime stamp is untouched")
	var reloaded: GraphProcgenConfig = load(_PRESET_PATH)
	assert_eq(reloaded, src, "sanity: load() hands back the one cached instance this test guards")


func test_a_fresh_config_copies_too() -> void:
	var cfg := GraphProcgenConfig.new()
	cfg.topology.node_count = 12
	var copy := cfg.private_copy()
	copy.topology.node_count = 99
	assert_eq(cfg.topology.node_count, 12)
