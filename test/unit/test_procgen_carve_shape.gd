extends GutTest

## ArchetypePolicy.archetype stamping (docs/domain/skillnode-emblem.md /
## #237's "all triangles regardless of archetype" fix, cut over to the
## Archetype resource by #312): procgen must carry an archetype's own
## Archetype (and its CarveShape) onto the SkillNode it generates.

const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"
@warning_ignore("shadowed_global_identifier")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")


func test_archetype_carve_shape_reaches_the_generated_node() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	# #349: topology/content are top-level module .tres (ExtResource);
	# duplicate(true) above does NOT cross that boundary, so both need their
	# own re-duplication before mutating (acceptance 4's trap, one level
	# deeper for `content` — see the comment below on the archetype ref).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 60
	cfg.n_random_starters = 0
	cfg.seed = 3

	var shape := PolygonCarveShape.new()
	shape.sides = 9
	cfg.content = cfg.content.duplicate(true)
	var tagged_archetype: StringName = cfg.content.archetypes[0].id
	# `archetype` is an ExtResource (archetypes/strength.tres) — cfg.duplicate(true)
	# does NOT deep-duplicate across a resource file boundary, only inline
	# sub-resources. Mutating it in place would corrupt the shared, cached
	# strength.tres singleton for every other test/consumer that loads it.
	cfg.content.archetypes[0].archetype = cfg.content.archetypes[0].archetype.duplicate(true)
	cfg.content.archetypes[0].archetype.carve_shape = shape

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])

	var found_tagged := false
	for n in nodes:
		if n.get_meta("archetype", &"") == tagged_archetype:
			# Compared BY VALUE, not by identity. Since #349 split the config into
			# top-level modules, `generate()` defensively re-duplicates
			# `config.content` on entry (it mutates `budget_policy.budget_field`
			# in place, and `duplicate(true)` no longer crosses that boundary).
			# The archetype this test inlines is therefore deep-copied on the way
			# through, so `carve_shape` arrives as an equal instance rather than
			# the same one. Production is unaffected: archetypes are ExtResources
			# and `duplicate(true)` never crosses a resource file boundary.
			assert_true(n.archetype.carve_shape is PolygonCarveShape, "the archetype's own carve_shape must reach its nodes")
			assert_eq(n.archetype.carve_shape.sides, shape.sides, "and it must be the 9-sided shape this test authored, not the class default")
			found_tagged = true
	assert_true(found_tagged, "expected at least one node of the tagged archetype")


## Regression test for #312: every archetype now carries its own carve shape
## (the six archetypes/*.tres resources), so every generated node draws its
## own shape instead of the class-default triangle. This inverts the old
## "leaves carve_shape null" pin, which was the bug this issue fixes.
func test_every_tagged_node_carries_its_archetypes_shape() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 60
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
	# Side count per archetype id — non-null shapes alone would still pass if
	# every archetype collapsed back to one shape, which IS the bug (#302: "every
	# procgen node in the game draws a triangle"). Shape-READABILITY is the
	# property, so assert the shapes actually differ across territories.
	var sides_by_archetype: Dictionary = {}
	for n in nodes:
		var arch_id: StringName = n.get_meta("archetype", &"")
		if arch_id != &"":
			found_tagged = true
			assert_not_null(n.archetype, "an archetype-tagged node must carry its Archetype resource")
			assert_not_null(n.archetype.carve_shape, "every archetype now carves its own shape, not the all-triangles default")
			var poly := n.archetype.carve_shape as PolygonCarveShape
			if poly != null:
				sides_by_archetype[arch_id] = poly.sides
	assert_true(found_tagged, "expected at least one archetype-tagged node")

	var distinct_sides: Dictionary = {}
	for sides in sides_by_archetype.values():
		distinct_sides[sides] = true
	assert_gt(distinct_sides.size(), 1,
			"territories must be shape-READABLE: %d archetypes generated but only %d distinct carve shape(s) — %s"
					% [sides_by_archetype.size(), distinct_sides.size(), sides_by_archetype])
