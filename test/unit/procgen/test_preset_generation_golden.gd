extends GutTest

## Characterization fixture for [GraphProcgen]'s output shape (#349 acceptance
## 3 & 6: "generation is byte-identical to master"). This is a PREREQUISITE
## for #349's config/module split, not that migration itself — the golden
## data below was captured from CURRENT MASTER, before any migration touches
## `procgen/**`. That ordering matters: if the migration worker also built the
## snapshot, it would be comparing its own post-migration output to itself —
## green, and proving nothing.
##
## Covers BOTH shipped presets end to end: every node's stable id, position,
## archetype, and FULL modifier set (not a count — a botched field migration
## shows up here), every edge as a canonicalized (min,max) stable-id pair, and
## the ordered starting-node list. See `gh issue view 349 --comments`.
##
## Fixtures live at `test/unit/procgen/fixtures/<preset>.golden.txt` —
## committed, human-diffable, deterministically ordered (sorted node ids,
## canonicalized edge pairs, fixed 6-decimal floats).
##
## Regenerating a fixture is a DELIBERATE act, never a way to turn a red test
## green:
##   1. Flip `_REGENERATE` below to `true` (or run
##      `mise run procgen-golden-regenerate`, which does the same thing from
##      the CLI without hand-editing this file).
##   2. Run this script alone:
##      `mise run test:one -- res://test/unit/procgen/test_preset_generation_golden.gd`
##   3. Flip `_REGENERATE` back to `false`.
##   4. Commit the rewritten fixture(s) with a message that justifies WHY
##      GraphProcgen's output was supposed to change.

const _PRESETS := {
	"first_level": "res://procgen/presets/first_level/first_level.tres",
	"coop_versus": "res://procgen/presets/coop_versus/coop_versus.tres",
}
const _FIXTURE_DIR := "res://test/unit/procgen/fixtures/"

## Any fixed nonzero seed — GraphProcgen.generate asserts non-zero (#457, the
## unresolved-seed sentinel). Sharing one seed across both presets is fine:
## each preset's own shape_mask / archetypes / pools diverge the RNG stream
## immediately.
const _SEED := 424242

## See the docstring above. Never flip this to make a failing comparison
## pass — that defeats the entire point of a characterization test.
const _REGENERATE := false


func _fresh_config(preset_path: String) -> GraphProcgenConfig:
	# generate() mutates the config in place (mask size_for, the propagated
	# outer_radius) and load() is cached, so every pass needs its own copy.
	var cfg: GraphProcgenConfig = (load(preset_path) as GraphProcgenConfig).duplicate(true)
	cfg.seed = _SEED
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Dictionary:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return {"graph": graph, "result": result}


static func _fmt_float(v: float) -> String:
	return "%.6f" % v


## One node's canonical text block: a NODE header line plus one sorted MOD
## line per entry in [member SkillNode.modifiers] (entity-scoped — the field
## procgen actually writes; see GraphProcgen.generate's per-node loop). Sorted
## by (stat_id, operation) rather than left in draw/aggregation order: after
## `_roll_modifiers_v4`'s fuse step those pairs are unique per node, so this
## reorder is content-only and can't hide a real value regression behind a
## harmless change to internal draw order.
static func _node_block(id: int, node: SkillNode) -> String:
	var arch_id := String(node.archetype.id) if node.archetype != null else ""
	var lines := PackedStringArray()
	lines.append("NODE %d %s %s %s" % [
		id, _fmt_float(node.position.x), _fmt_float(node.position.y), arch_id,
	])
	var mods: Array[StatModifier] = node.modifiers.duplicate()
	mods.sort_custom(func(a: StatModifier, b: StatModifier) -> bool:
		if a.stat_id != b.stat_id:
			return String(a.stat_id) < String(b.stat_id)
		return a.operation < b.operation)
	for m in mods:
		# Procgen-drawn modifiers are plain static rolls (no formula) today,
		# but capture it anyway rather than silently dropping a field a future
		# pool entry might set.
		var formula_tag := "-"
		if m.formula != null:
			formula_tag = JSON.stringify(m.formula.to_dict(), "", true)
		lines.append("  MOD %s %d %s %d %s" % [
			String(m.stat_id), m.operation, _fmt_float(m.value), m.priority, formula_tag,
		])
	return "\n".join(lines)


## Build the canonical snapshot Dictionary from a live generate() result:
## `{seed, node_count, nodes: Dictionary[int, String], edges: Array[Vector2i],
## starters: Array[int]}`. [method _parse_fixture] parses a committed fixture
## back into this exact shape, so both directions feed the same comparison
## logic in [method _assert_matches].
static func _build_snapshot(cfg: GraphProcgenConfig, graph: Graph, result: Dictionary) -> Dictionary:
	var nodes_arr: Array = result.get("nodes", [])
	var nodes: Dictionary[int, String] = {}
	for n in nodes_arr:
		var id := graph.get_stable_id(n)
		nodes[id] = _node_block(id, n)

	# Canonicalize each edge to (min,max) stable ids so direction / insertion
	# order can't cause a false diff; self-loops (from == to) survive as (a,a).
	var edges: Array[Vector2i] = []
	for e in graph.get_edges():
		var a := graph.get_stable_id(e.from)
		var b := graph.get_stable_id(e.to)
		edges.append(Vector2i(mini(a, b), maxi(a, b)))
	edges.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return p.x < q.x if p.x != q.x else p.y < q.y)

	# Order preserved on purpose: starting_nodes[i] pairs with
	# config.starting_points[i] / the starter_placement plan (see
	# GraphProcgen.generate's docstring) — that index correspondence is
	# meaningful, unlike edges/nodes which sort for human-diffability.
	var starters: Array[int] = []
	for n in result.get("starting_nodes", []):
		starters.append(graph.get_stable_id(n))

	return {
		"seed": cfg.seed,
		"node_count": nodes_arr.size(),
		"nodes": nodes,
		"edges": edges,
		"starters": starters,
	}


static func _render_text(preset_path: String, data: Dictionary) -> String:
	var out := PackedStringArray()
	out.append("# GOLDEN FIXTURE for %s" % preset_path)
	out.append("# Generated by test/unit/procgen/test_preset_generation_golden.gd — DO NOT hand-edit.")
	out.append("# Characterizes GraphProcgen.generate()'s output for #349's config/module migration to")
	out.append("# be judged against, captured from master BEFORE that migration touched procgen/**. See")
	out.append("# `gh issue view 349 --comments` (acceptance 3 & 6).")
	out.append("#")
	out.append("# Regenerating this file is a DELIBERATE act, never a way to turn a red test green: flip")
	out.append("# `_REGENERATE` in the test script (or run `mise run procgen-golden-regenerate`), rerun the")
	out.append("# script alone, flip `_REGENERATE` back, and justify WHY generation was supposed to change")
	out.append("# in the commit message.")
	out.append("SEED %d" % int(data.seed))
	out.append("NODE_COUNT %d" % int(data.node_count))
	var nodes: Dictionary = data.nodes
	var ids: Array = nodes.keys()
	ids.sort()
	for id in ids:
		out.append(nodes[id])
	for p: Vector2i in data.edges:
		out.append("EDGE %d %d" % [p.x, p.y])
	for id in data.starters:
		out.append("STARTER %d" % id)
	return "\n".join(out) + "\n"


## Inverse of [method _render_text] / [method _build_snapshot] — parses a
## committed fixture back into the same snapshot shape. No lambda-closure
## helper here on purpose (see `.claude/rules/gdscript-pitfalls.md` /
## project memory on lambda-captures-by-value): the flush-current-node step is
## inlined at both places it's needed rather than factored into a Callable
## that would close over a stale copy of `current_id` / `current_lines`.
static func _parse_fixture(text: String) -> Dictionary:
	var seed_val := 0
	var node_count := 0
	var nodes: Dictionary[int, String] = {}
	var edges: Array[Vector2i] = []
	var starters: Array[int] = []

	var current_id := -1
	var current_lines := PackedStringArray()

	for raw_line in text.split("\n"):
		if raw_line.strip_edges().is_empty() or raw_line.begins_with("#"):
			continue
		if raw_line.begins_with("  MOD "):
			current_lines.append(raw_line)
			continue
		if current_id >= 0:
			nodes[current_id] = "\n".join(current_lines)
			current_id = -1
			current_lines = PackedStringArray()
		var parts := raw_line.split(" ")
		match parts[0]:
			"SEED":
				seed_val = int(parts[1])
			"NODE_COUNT":
				node_count = int(parts[1])
			"NODE":
				current_id = int(parts[1])
				current_lines.append(raw_line)
			"EDGE":
				edges.append(Vector2i(int(parts[1]), int(parts[2])))
			"STARTER":
				starters.append(int(parts[1]))
	if current_id >= 0:
		nodes[current_id] = "\n".join(current_lines)

	return {
		"seed": seed_val,
		"node_count": node_count,
		"nodes": nodes,
		"edges": edges,
		"starters": starters,
	}


static func _write_fixture(preset_key: String, preset_path: String, data: Dictionary) -> void:
	var f := FileAccess.open(_FIXTURE_DIR + preset_key + ".golden.txt", FileAccess.WRITE)
	f.store_string(_render_text(preset_path, data))
	f.close()


func _load_fixture(preset_key: String) -> Dictionary:
	var path := _FIXTURE_DIR + preset_key + ".golden.txt"
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "missing golden fixture %s — run with _REGENERATE=true once to create it" % path)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	return _parse_fixture(text)


## Per-node comparison, not a whole-blob diff — a corrupted value must name
## which preset AND which node in the failure message (#349's acceptance 3).
func _assert_matches(preset_key: String, golden: Dictionary, actual: Dictionary) -> void:
	assert_eq(int(actual.seed), int(golden.seed),
		"%s: fixture's SEED header doesn't match _SEED — was the fixture hand-edited?" % preset_key)
	assert_eq(int(actual.node_count), int(golden.node_count),
		"%s: node count differs from golden (%d vs %d)" % [preset_key, actual.node_count, golden.node_count])

	var golden_nodes: Dictionary = golden.nodes
	var actual_nodes: Dictionary = actual.nodes
	var golden_ids: Array = golden_nodes.keys()
	var actual_ids: Array = actual_nodes.keys()
	golden_ids.sort()
	actual_ids.sort()
	assert_eq(actual_ids, golden_ids, "%s: node id set differs from golden" % preset_key)

	for id in golden_ids:
		if not actual_nodes.has(id):
			continue  # already reported by the id-set assert above
		assert_eq(String(actual_nodes[id]), String(golden_nodes[id]),
			"%s node %d: mismatch vs golden\n--- golden ---\n%s\n--- actual ---\n%s"
			% [preset_key, id, golden_nodes[id], actual_nodes[id]])

	assert_eq(actual.edges, golden.edges, "%s: edge set differs from golden" % preset_key)
	assert_eq(actual.starters, golden.starters, "%s: starting-node list differs from golden" % preset_key)


func _run_preset(preset_key: String) -> void:
	var preset_path: String = _PRESETS[preset_key]
	var cfg := _fresh_config(preset_path)
	var gen := await _generate(cfg)
	var snapshot := _build_snapshot(cfg, gen.graph, gen.result)

	if _REGENERATE:
		_write_fixture(preset_key, preset_path, snapshot)
		fail_test(
			"_REGENERATE is true — rewrote %s.golden.txt. Flip _REGENERATE back to false, "
			% preset_key
			+ "re-run to confirm green, and commit the fixture with a message justifying WHY "
			+ "generation was supposed to change.")
		return

	var golden := _load_fixture(preset_key)
	_assert_matches(preset_key, golden, snapshot)

	# Acceptance 2: repeat generate() in-process, same seed, must canonicalize
	# identically — a fixture that is flaky by construction (unstable sort,
	# an unseeded roll) is worse than none.
	var cfg_b := _fresh_config(preset_path)
	var gen_b := await _generate(cfg_b)
	var snapshot_b := _build_snapshot(cfg_b, gen_b.graph, gen_b.result)
	assert_eq(_render_text(preset_path, snapshot_b), _render_text(preset_path, snapshot),
		"%s: repeat generate() call in one process produced different output — ordering nondeterminism"
		% preset_key)


func test_first_level_matches_golden() -> void:
	await _run_preset("first_level")


func test_coop_versus_matches_golden() -> void:
	await _run_preset("coop_versus")
