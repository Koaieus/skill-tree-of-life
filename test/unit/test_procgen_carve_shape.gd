extends GutTest

## ArchetypePolicy.archetype stamping (docs/domain/skillnode-emblem.md /
## #237's "all triangles regardless of archetype" fix, cut over to the
## Archetype resource by #312): procgen must carry an archetype's own
## Archetype (and its CarveShape) onto the SkillNode it generates.

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
	# `archetype` is an ExtResource (archetypes/strength.tres) — cfg.duplicate(true)
	# does NOT deep-duplicate across a resource file boundary, only inline
	# sub-resources. Mutating it in place would corrupt the shared, cached
	# strength.tres singleton for every other test/consumer that loads it.
	cfg.archetypes[0].archetype = cfg.archetypes[0].archetype.duplicate(true)
	cfg.archetypes[0].archetype.carve_shape = shape

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])

	var found_tagged := false
	for n in nodes:
		if n.get_meta("archetype", &"") == tagged_archetype:
			assert_eq(n.archetype.carve_shape, shape, "the archetype's own carve_shape must reach its nodes")
			found_tagged = true
	assert_true(found_tagged, "expected at least one node of the tagged archetype")


## Regression test for #312: every archetype now carries its own carve shape
## (the six archetypes/*.tres resources), so every generated node draws its
## own shape instead of the class-default triangle. This inverts the old
## "leaves carve_shape null" pin, which was the bug this issue fixes.
func test_every_tagged_node_carries_its_archetypes_shape() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	cfg.node_count = 60
	cfg.n_random_starters = 0
	cfg.seed = 3

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])
	assert_gt(nodes.size(), 0)
	var found_tagged := false
	for n in nodes:
		if n.get_meta("archetype", &"") != &"":
			found_tagged = true
			assert_not_null(n.archetype, "an archetype-tagged node must carry its Archetype resource")
			assert_not_null(n.archetype.carve_shape, "every archetype now carves its own shape, not the all-triangles default")
	assert_true(found_tagged, "expected at least one archetype-tagged node")
