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
## e0b838af (the tip this child branched from), and re-captured for #1793's
## element pool rolls (a deliberate content change), with `node_count` pinned to
## [constant GOLDEN_NODE_COUNT] on a private copy of each preset. Scope: the
## hub's serial chain (#1776..#1781). Child 5 may retire this file once the
## chain lands — the 2026-08 goldens were retired because content is
## unsettled (`test_pool_seed_values.gd`); a deliberate content or preset
## tune going red here is re-captured, never "fixed" in the pipeline.
##
## Wall time at e0b838af: 7.6 s script (3.4 first_level / 3.2 coop_versus /
## 1.0 self-check), 9.9 s task wall including boot — integration tier,
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
	"first_level:1": "00f952edf3b10df09623c987da66088b48af2ce8991d89863a8b31c80e42c3eb",
	"first_level:20261105": "aa8c502c66572603c52510274a7b4e5dbafcd5c7ef047ae7fbec71a363b65a96",
	"first_level:777": "b78bc3cd89d573b488610a5784b6c139b22d05d2a4ca91c8c0ed5c16eb19685f",
	"coop_versus:1": "c6a8feb69cc0c4a2de4187ef7f2ff2f93210077551fd9010591e0433a5fae63e",
	"coop_versus:20261105": "073333040b03964999313d4f0e54adf8a6af673777f2768a97556e833b07e5d7",
	"coop_versus:777": "0362419fb87a3f504d8240dbf408397674b8642a0639cc5cc41d803dc719d013",
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
		# `face` is a Resource: hash its path, never `str()` (an instance id
		# that shifts with whatever ran earlier in the shard).
		var face: Resource = b.get("face") as Resource
		lines.append("B %d size=%d stake=%d prune=%d face=%s face_seed=%d fp=[%s]" % [
			graph.get_stable_id(b.get("node")),
			int(b.get("size")),
			int(b.get("stake_level", 1)),
			int(b.get("prune_seed", 0)),
			face.resource_path if face != null else "-",
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
