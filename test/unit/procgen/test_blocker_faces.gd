extends GutTest

## #1654 acceptance 2 — the face roll is seed-deterministic, rides its own
## stream (faces off leaves every other blocker draw untouched) and honours
## [member GraphProcgenBlockers.faceless_weight].


func _build_config(rng_seed: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.topology = GraphProcgenTopology.new()
	cfg.topology.node_count = 60
	cfg.seed = rng_seed
	cfg.shape = GraphProcgenShape.new()
	cfg.shape.shape_mask = CircularShapeMask.new()
	cfg.starting = GraphProcgenStartingPoints.new()
	cfg.content = GraphProcgenContent.new()
	cfg.blockers = GraphProcgenBlockers.new()
	cfg.blockers.blocker_per_small = 10
	cfg.blockers.blocker_per_medium = 20
	cfg.blockers.blocker_per_large = 20
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Array:
	var graph: Graph = autofree(load("res://graph/graph.tscn").instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return result.get("blockers", [])


func _face_key(placement: Dictionary) -> String:
	var face: CoreClass = placement.get("face")
	return "%s#%d" % [face.resource_path if face != null else "-", int(placement.get("face_seed", 0))]


## Everything a placement carries except its face, positions standing in for nodes.
func _rest(placement: Dictionary) -> Array:
	var fp := []
	for n: SkillNode in placement.get("footprint", []):
		fp.append(n.position)
	return [(placement.get("node") as SkillNode).position, placement.get("size"),
			placement.get("prune_seed"), fp, placement.get("stake_level")]


func test_same_seed_same_faces() -> void:
	var a: Array = await _generate(_build_config(777))
	var b: Array = await _generate(_build_config(777))
	assert_gt(a.size(), 0, "the fixture places blockers")
	assert_eq(a.map(_face_key), b.map(_face_key), "same seed, same faces and seeds")
	assert_true(a.any(func(p: Dictionary) -> bool: return p.get("face") != null),
			"faces are on by default")


func test_faces_off_leaves_every_other_draw_identical() -> void:
	var on: Array = await _generate(_build_config(4242))
	var cfg_off := _build_config(4242)
	cfg_off.blockers.faces = []
	var off: Array = await _generate(cfg_off)
	assert_eq(off.map(_rest), on.map(_rest), "nodes, sizes, prune seeds, footprints, stakes unchanged")
	assert_false(off.any(func(p: Dictionary) -> bool: return p.get("face") != null),
			"faces off rolls no face")


func test_faceless_weight_is_honoured() -> void:
	var mod := GraphProcgenBlockers.new()
	mod.faceless_weight = 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var indices := range(1000)
	var rolled: Dictionary = mod.roll_faces(indices, rng)
	assert_eq(rolled.size(), 1000, "one roll per placement")
	var faceless := 0
	for idx in indices:
		if (rolled.get(idx, {}) as Dictionary).get("face") == null:
			faceless += 1
	var expected: float = mod.faceless_weight / (mod.faceless_weight + float(mod.faces.size()))
	assert_almost_eq(faceless / 1000.0, expected, 0.04, "faceless share ≈ weight / total")
