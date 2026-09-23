extends GutTest

## GraphProcgen.generate() never writes to the config it is handed: it
## resolves on its own copy and returns that as `result.config`.

const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"


## A config shaped like the trap: auto-scaled mask + an opted-in gradient
## (outer_radius = 0) that generation back-fills. Built from scratch, so the
## test never reaches the cached on-disk preset.
func _config() -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.seed = 425
	cfg.topology.node_count = 40
	var mask := CircularShapeMask.new()
	mask.auto_scale = true
	cfg.shape.shape_mask = mask
	cfg.content.budget_policy = BudgetPolicy.new()
	cfg.content.budget_policy.budget_field = RadialGradientField.new()
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Dictionary:
	var graph: Graph = autofree((load("res://graph/graph.tscn") as PackedScene).instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	return await GraphProcgen.generate(cfg, graph)


func _fingerprint(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for n in result.get("nodes", []):
		var sn: SkillNode = n
		parts.append("%d,%d" % [roundi(sn.position.x), roundi(sn.position.y)])
	return "/".join(parts)


func test_generate_leaves_the_callers_config_untouched() -> void:
	var cfg := _config()
	var shape := cfg.shape
	var content := cfg.content
	var mask_aabb := cfg.shape.shape_mask.aabb()
	await _generate(cfg)
	assert_same(cfg.shape, shape, "generate() rebound the caller's config.shape")
	assert_same(cfg.content, content, "generate() rebound the caller's config.content")
	assert_eq((content.budget_policy.budget_field as RadialGradientField).outer_radius, 0.0,
			"generate() back-filled the caller's gradient")
	assert_eq(cfg.shape.shape_mask.aabb(), mask_aabb, "generate() auto-scaled the caller's mask")


func test_generating_twice_from_one_config_is_identical() -> void:
	var cfg := _config()
	var first := await _generate(cfg)
	var second := await _generate(cfg)
	assert_eq(_fingerprint(first), _fingerprint(second), "run 2 started from run 1's resolved state")
	assert_gt(_fingerprint(first).length(), 16, "sanity: generation produced nodes")


func test_result_carries_the_resolved_config() -> void:
	var cfg := _config()
	var authored := cfg.shape.shape_mask.aabb()
	var result := await _generate(cfg)
	assert_true(result.has("config"), "the happy path returns the resolved config")
	var resolved: GraphProcgenConfig = result.get("config")
	assert_not_same(resolved, cfg)
	assert_ne(resolved.shape.shape_mask.aabb(), authored, "the resolved mask is auto-scaled")
	assert_gt((resolved.content.budget_policy.budget_field as RadialGradientField).outer_radius, 0.0,
			"the resolved gradient is back-filled")


func test_the_zero_node_return_also_carries_the_config() -> void:
	var cfg := _config()
	cfg.topology.node_count = 0
	var result := await _generate(cfg)
	assert_true(result.has("config"), "the early return must carry the same key as the happy path")


func test_the_shipped_preset_is_not_mutated() -> void:
	var cfg: GraphProcgenConfig = load(_PRESET_PATH)
	var shape := cfg.shape
	var content := cfg.content
	var aabb := cfg.shape.shape_mask.aabb()
	var small: GraphProcgenConfig = cfg.duplicate()
	small.topology = cfg.topology.duplicate(true)
	small.topology.node_count = 60
	small.seed = 3
	await _generate(small)
	assert_same(cfg.shape, shape)
	assert_same(cfg.content, content)
	assert_eq(cfg.shape.shape_mask.aabb(), aabb)
