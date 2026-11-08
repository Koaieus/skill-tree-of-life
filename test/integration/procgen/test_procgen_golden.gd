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
## The six literals in [constant EXPECTED] were captured on master at
## e0b838af (the tip this child branched from), with `node_count` pinned to
## [constant GOLDEN_NODE_COUNT] on a private copy of each preset. Scope: the
## hub's serial chain (#1776..#1781). Child 5 may retire this file once the
## chain lands — the 2026-08 goldens were retired because content is
## unsettled (`test_pool_seed_values.gd`); a deliberate content or preset
## tune going red here is re-captured, never "fixed" in the pipeline.
##
## Wall time at e0b838af: 8.4 s script (3.9 first_level / 3.4 coop_versus /
## 1.0 self-check), 10.7 s task wall including boot — integration tier,
## under its 15 s budget. At the authored 800 nodes it was 16.3 s.

const _FIRST_LEVEL := "res://procgen/presets/first_level/first_level.tres"
const _COOP_VERSUS := "res://procgen/presets/coop_versus/coop_versus.tres"
const SEEDS: Array[int] = [1, 20261105, 777]
## Node count pinned on the private copy of every preset (tentative knob).
## The authored topologies carry 800 nodes, which put seven generations at
## 16.3 s per script (7.3 / 6.7 / 2.3 per test) — over the integration
## tier's 15 s budget. Every pipeline stage runs at any count, so the hash
## loses no detection power at 400; the precedent is
## `test_procgen_connectivity.gd` setting `node_count` on a copy.
const GOLDEN_NODE_COUNT := 400

## `"<preset basename>:<seed>"` → sha256 of [method fingerprint].
const EXPECTED := {
	"first_level:1": "273c15962f38fa8bd0af9c3b4b8fbe4e769a3fb8f9fedc63c4ae56473490c602",
	"first_level:20261105": "be0e504e613e2dbd121111421799daab410d8b3dbc57128c7b8dc27923f1c489",
	"first_level:777": "a1c5f209c3eb1a2a326f3bcd5614ff40742cd7de657f8d0ef78f7e84d71a15d8",
	"coop_versus:1": "ae80d070db0b37fededa885fa918ac47d4c037df1dd40565105a043c32e93bd3",
	"coop_versus:20261105": "78301c168febc8c45f308f47ad73609295c6ebeb63588a36897e38346b88f8f7",
	"coop_versus:777": "4ce4fce894708f68cdbf1dde5703b7dc9d8fe1196de797a36a3c4a040b893791",
}


func _load_config(preset_path: String, seed: int) -> GraphProcgenConfig:
	var src: GraphProcgenConfig = load(preset_path)
	var cfg: GraphProcgenConfig = src.private_copy()
	cfg.topology.node_count = GOLDEN_NODE_COUNT
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
