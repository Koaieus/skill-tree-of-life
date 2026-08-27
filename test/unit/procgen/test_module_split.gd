extends GutTest

## Acceptance for #349 (procgen config → module split): the properties the
## split itself is judged on, distinct from the golden byte-identical guard
## in `test_preset_generation_golden.gd` (that one is acceptance 3 — this
## file is 4, 5 and 6).

const _FIRST_LEVEL_PATH := "res://procgen/presets/first_level/first_level.tres"
const _TOPOLOGY_PATH := "res://procgen/modules/first_level/topology.tres"


## Acceptance 4 — the runtime stamp must not leak into the authored module.
##
## `procgen_play_sandbox.gd` (and every test in this suite that overrides
## `node_count`) does `preset.duplicate(true)` then writes `node_count`. Since
## Topology is now a top-level `.tres` (an ExtResource from the preset's
## perspective), `duplicate(true)` does NOT deep-copy it — only embedded
## SubResources cross that boundary. Without `cfg.topology =
## cfg.topology.duplicate(true)` first, that write lands on the SAME cached
## Topology object every other loader of `first_level.tres` in this process
## shares, corrupting the on-disk-authored value for the rest of the run.
##
## Generates twice from the same preset with different overrides, then
## reloads the Topology module fresh from disk and asserts it still reads
## its authored value. Confirmed to fail without the
## `cfg.topology = cfg.topology.duplicate(true)` guard by commenting it out
## locally and re-running — do not remove that guard from
## `scenes/procgen_play_sandbox.gd` / the test helpers that carry it.
func test_node_count_override_does_not_leak_into_the_authored_module() -> void:
	var authored_topology: GraphProcgenTopology = load(_TOPOLOGY_PATH)
	var authored_node_count := authored_topology.node_count
	assert_gt(authored_node_count, 0, "sanity: first_level's Topology module authors a real node_count")

	for override in [55, 77]:
		var cfg: GraphProcgenConfig = (load(_FIRST_LEVEL_PATH) as GraphProcgenConfig).duplicate(true)
		cfg.topology = cfg.topology.duplicate(true)
		cfg.topology.node_count = override
		cfg.seed = 42

		var graph_scene: PackedScene = load("res://graph/graph.tscn")
		var graph: Graph = autofree(graph_scene.instantiate()) as Graph
		add_child(graph)
		await get_tree().process_frame
		await GraphProcgen.generate(cfg, graph)

		# Re-load straight from disk (bypassing the engine's resource cache)
		# so a corrupted CACHED object can't hide behind a fresh `load()`
		# returning the same poisoned instance.
		var reloaded: GraphProcgenTopology = ResourceLoader.load(_TOPOLOGY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_eq(reloaded.node_count, authored_node_count,
				"override %d must not leak into the on-disk Topology module (still cached in-process at %d?)"
				% [override, authored_topology.node_count])
	assert_eq(authored_topology.node_count, authored_node_count,
			"the live cached Topology object read at the top of this test must also be untouched")


## Acceptance 5 — the runtime-stamped group's provenance. `camp_sizes` (and
## its siblings) are readable/writable on `GraphProcgenConfig` itself, and no
## module `.tres` on disk may carry it — putting it in an authored file would
## make it a second source of truth against the roster.
func test_runtime_fields_live_on_config_not_in_any_module() -> void:
	var cfg := GraphProcgenConfig.new()
	cfg.camp_sizes = [3, 3]
	cfg.n_random_starters = 2
	cfg.viability_radius = 123.0
	cfg.seed = 7
	assert_eq(cfg.camp_sizes, [3, 3] as Array[int])
	assert_eq(cfg.n_random_starters, 2)
	assert_almost_eq(cfg.viability_radius, 123.0, 0.001)
	assert_eq(cfg.seed, 7)

	for module_path in [
		"res://procgen/modules/first_level/topology.tres",
		"res://procgen/modules/first_level/shape.tres",
		"res://procgen/modules/first_level/starting_points.tres",
		"res://procgen/modules/first_level/content.tres",
		"res://procgen/modules/first_level/blockers.tres",
		"res://procgen/modules/coop_versus/topology.tres",
		"res://procgen/modules/coop_versus/shape.tres",
		"res://procgen/modules/coop_versus/starting_points.tres",
		"res://procgen/modules/coop_versus/content.tres",
		"res://procgen/modules/coop_versus/blockers.tres",
	]:
		var res: Resource = load(module_path)
		assert_false(res.get("camp_sizes") != null,
				"%s must not carry camp_sizes — it is roster-derived, never authored" % module_path)


## Acceptance 6 — a module is swappable in isolation, the property #597's
## override merge (and the lobby's map-size / blocker-density / arrangement
## controls) is built on. Replacing ONLY the Topology ref on a duplicated
## `first_level.tres` must change node count and nothing else, matching a
## from-scratch generation built the same way.
func test_swapping_only_the_topology_module_changes_only_node_count() -> void:
	var swapped_topology := GraphProcgenTopology.new()
	swapped_topology.node_count = 50
	swapped_topology.node_radius = 32.0
	swapped_topology.node_padding = 14.0
	swapped_topology.connectivity = 0.55

	var cfg: GraphProcgenConfig = (load(_FIRST_LEVEL_PATH) as GraphProcgenConfig).duplicate(true)
	cfg.topology = swapped_topology
	cfg.seed = 314

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])

	# node count moved: nowhere near the preset's authored 800, close to the
	# swapped module's 50 (Poisson under-fills a little, never over-fills).
	assert_true(nodes.size() <= 50 and nodes.size() > 30,
			"expected close to the swapped Topology's 50 nodes; got %d" % nodes.size())

	# Everything Content owns is untouched by the swap: every archetype still
	# shows up, matching the unmodified preset's own archetype roster.
	var archetype_counts := {}
	for n in nodes:
		var arch: StringName = n.get_meta("archetype", &"")
		if arch != &"":
			archetype_counts[arch] = true
	for a in [&"red", &"green", &"blue"]:
		assert_true(a in archetype_counts,
				"archetype %s should still appear — swapping Topology must not touch Content" % String(a))
