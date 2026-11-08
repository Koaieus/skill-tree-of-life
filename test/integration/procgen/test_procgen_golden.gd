extends GutTest

## #1775 (hub #422, child −1) — the golden-hash guard for the
## `graph_procgen.gd` phase split. Every later child of the hub extracts a
## phase into `procgen/phases/` and is RED-then-green against THIS file: a
## red here means the extraction changed a draw (RNG salt, draw order, a
## resolved value), which the hub forbids — same seed, byte-identical graph.
##
## 3 seeds × 2 presets, generated synchronously (no progress callback) on a
## mounted `graph.tscn`, folded by [method fingerprint] into one sha256 over:
## every node in Graph child order (stable id, position rounded to 0.01,
## radii, archetype, subtype, the STORED `authored_modifiers` triples — never
## the runtime `modifiers` — addon class names, stake), every edge as an
## ordered stable-id pair, every blocker entry of the result Dictionary, and
## the resolved `result.config.seed`. Positions are rounded for float-text
## stability; everything else is exact.
##
## The six literals in [constant EXPECTED] were captured at this child's
## landing sha on master (see the issue). Scope: the hub's serial chain
## (#1776..#1781). Child 5 may retire this file once the chain lands — the
## 2026-08 goldens were retired for the same reason (content is unsettled; a
## tune must never go red here, so re-capture on a deliberate content change).
##
## Wall time: see the issue / the `test:one` run recorded at landing;
## integration tier, under its 15 s budget.

const _FIRST_LEVEL := "res://procgen/presets/first_level/first_level.tres"
const _COOP_VERSUS := "res://procgen/presets/coop_versus/coop_versus.tres"
const SEEDS: Array[int] = [1, 20261105, 777]

## `"<preset basename>:<seed>"` → sha256 of [method fingerprint].
const EXPECTED := {
	"first_level:1": "PLACEHOLDER",
	"first_level:20261105": "PLACEHOLDER",
	"first_level:777": "PLACEHOLDER",
	"coop_versus:1": "PLACEHOLDER",
	"coop_versus:20261105": "PLACEHOLDER",
	"coop_versus:777": "PLACEHOLDER",
}


func _load_config(preset_path: String, seed: int) -> GraphProcgenConfig:
	var src: GraphProcgenConfig = load(preset_path)
	var cfg: GraphProcgenConfig = src.private_copy()
	cfg.seed = seed
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Dictionary:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	result["_graph"] = graph
	return result


func _hash_for(preset_path: String, seed: int) -> String:
	var result: Dictionary = await _generate(_load_config(preset_path, seed))
	return fingerprint(result, result["_graph"] as Graph)


## One String over everything procgen decides for a generated graph. Node
## lines follow Graph child order; edge lines Graph edge order; blocker lines
## the result's `blockers` order. A later child may lift this to
## `test/support/` if a second test wants it.
static func fingerprint(result: Dictionary, graph: Graph) -> String:
	var lines := PackedStringArray()
	for node: SkillNode in graph.get_skill_nodes():
		var parts := PackedStringArray()
		parts.append("N %d" % graph.get_stable_id(node))
		parts.append("pos=%.2f,%.2f" % [node.position.x, node.position.y])
		parts.append("r=%s/%s" % [node.base_radius, node.base_inner_radius])
		parts.append("arch=%s" % (node.archetype.id if node.archetype != null else &"-"))
		parts.append("sub=%s" % (node.subtype.id if node.subtype != null else &"-"))
		parts.append("color=%s" % node.base_type_color.to_html())
		var mods := PackedStringArray()
		for m: StatModifier in node.authored_modifiers:
			mods.append("(%s,%d,%s)" % [m.stat_id, m.operation, m.value])
		parts.append("mods=[%s]" % ",".join(mods))
		var addons := PackedStringArray()
		for a: SkillNodeAddon in node.get_addons():
			var script: Script = a.get_script()
			var addon_name: String = a.get_class()
			if script != null:
				addon_name = script.get_global_name()
			addons.append(addon_name)
		parts.append("addons=[%s]" % ",".join(addons))
		parts.append("stake=%d" % node.stake_level)
		lines.append(" ".join(parts))
	for edge: Edge in graph.get_edges():
		lines.append("E %d-%d" % [graph.get_stable_id(edge.from), graph.get_stable_id(edge.to)])
	for b: Dictionary in result.get("blockers", []):
		var footprint := PackedStringArray()
		for f: SkillNode in b.get("footprint", []):
			footprint.append(str(graph.get_stable_id(f)))
		lines.append("B %d size=%d stake=%d prune=%d face=%s face_seed=%d fp=[%s]" % [
			graph.get_stable_id(b.get("node")),
			int(b.get("size")),
			int(b.get("stake_level", 1)),
			int(b.get("prune_seed", 0)),
			str(b.get("face")),
			int(b.get("face_seed", 0)),
			",".join(footprint),
		])
	var cfg: GraphProcgenConfig = result.get("config")
	lines.append("seed=%d" % (cfg.seed if cfg != null else 0))
	return "\n".join(lines).sha256_text()


func test_first_level_goldens() -> void:
	for seed in SEEDS:
		var key := "first_level:%d" % seed
		var got := await _hash_for(_FIRST_LEVEL, seed)
		assert_eq(got, EXPECTED[key], "%s: draw order or a resolved value changed" % key)


func test_coop_versus_goldens() -> void:
	for seed in SEEDS:
		var key := "coop_versus:%d" % seed
		var got := await _hash_for(_COOP_VERSUS, seed)
		assert_eq(got, EXPECTED[key], "%s: draw order or a resolved value changed" % key)


## Self-check: the fingerprint sees a topology change. A duplicated
## first_level config with `node_count + 1` must hash differently from the
## pinned seed-1 golden.
func test_node_count_plus_one_changes_hash() -> void:
	var cfg := _load_config(_FIRST_LEVEL, SEEDS[0])
	cfg.topology.node_count += 1
	var result: Dictionary = await _generate(cfg)
	var got := fingerprint(result, result["_graph"] as Graph)
	assert_ne(got, EXPECTED["first_level:1"], "node_count + 1 must change the golden")
