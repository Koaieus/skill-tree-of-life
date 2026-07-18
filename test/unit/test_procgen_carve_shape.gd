extends GutTest

## ArchetypePolicy.carve_shape stamping (docs/domain/skillnode-emblem.md /
## #237's "all triangles regardless of archetype" fix): procgen must carry an
## archetype's own CarveShape onto the SkillNode it generates, winning over
## SkillNode.archetype's fixed six-way quick-pick default.

const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")


func test_archetype_carve_shape_reaches_the_generated_node() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	cfg.node_count = 60
	cfg.n_random_starters = 0
	cfg.seed = 3

	var shape := PolygonCarveShape.new()
	shape.sides = 9
	var tagged_archetype: StringName = cfg.archetypes[0].id
	cfg.archetypes[0].carve_shape = shape

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])

	var found_tagged := false
	for n in nodes:
		if n.get_meta("base_type", &"") == tagged_archetype:
			assert_eq(n.carve_shape, shape, "the archetype's own carve_shape must reach its nodes")
			found_tagged = true
	assert_true(found_tagged, "expected at least one node of the tagged archetype")


func test_untagged_archetype_leaves_carve_shape_null() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	cfg.node_count = 60
	cfg.n_random_starters = 0
	cfg.seed = 3
	# No archetype gets a carve_shape here — every node should fall back to
	# SkillNode.archetype's quick-pick (get_emblem_contributions handles that,
	# not procgen), so procgen itself must leave carve_shape null throughout.

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])
	assert_gt(nodes.size(), 0)
	for n in nodes:
		assert_null(n.carve_shape, "no policy stamped a shape -> SkillNode.carve_shape stays null")
