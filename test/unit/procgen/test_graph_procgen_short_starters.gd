extends GutTest

## A starter placement that returns fewer points than the roster has
## participants must fail the generation, never zip later participants onto a
## neighbour's spawn. `CenterCoreStarters.plan` skips an unplaceable
## contender by design (test_center_core_starters.gd), so the guard lives in
## `GraphProcgen.generate`.


func _crowded_config() -> GraphProcgenConfig:
	var placement := CenterCoreStarters.new()
	placement.viability_radius = 3.0
	var cfg := GraphProcgenConfig.new()
	cfg.topology = GraphProcgenTopology.new()
	cfg.topology.node_count = 60
	cfg.seed = 3
	cfg.shape = GraphProcgenShape.new()
	var mask := CircularShapeMask.new()
	mask.radius = 150.0
	mask.auto_scale = false
	cfg.shape.shape_mask = mask
	cfg.camp_sizes = [1, 3] as Array[int]
	cfg.starting = GraphProcgenStartingPoints.new()
	cfg.starting.starter_placement = placement
	return cfg


func test_short_plan_fails_generation_with_empty_result() -> void:
	var graph: Graph = autofree((load("res://graph/graph.tscn") as PackedScene).instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(_crowded_config(), graph)
	assert_eq((result["nodes"] as Array).size(), 0, "no nodes on an unseatable roster")
	assert_eq((result["starting_nodes"] as Array).size(), 0, "no starting nodes either")
	assert_push_error("cannot seat")
