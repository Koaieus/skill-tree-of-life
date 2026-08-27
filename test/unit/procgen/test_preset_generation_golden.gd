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
## Also covers the rest of GraphProcgenConfig's Content group, since #349's
## Content module owns all of it, not just modifier_pool_set: each node's
## attached addons (`_roll_and_attach_addons`, walked via
## [method SkillNode.get_addons] so this also picks up any addon a
## [KeystonePlacement] mints via `Keystone.addon_scenes`) with their
## `local_modifiers`, spell grants (`GraphProcgenSpellGrants.distribute`,
## captured as the granted [SpellDef.id]), and a stamped [SkillNode.keystone]'s
## identity. `MinNearStartingPoints` / `RandomBudgetBoost` (the other two
## `guaranteed_placements` entries both presets author) and `archetype_stamps`
## (authored empty in both presets today) are deliberately NOT captured as
## their own fields — see the comments at their capture sites for why each is
## either fully implied by what's already here, or genuinely absent.
##
## Fixtures live at `test/unit/procgen/fixtures/<preset>.golden.txt` —
## committed, human-diffable, deterministically ordered (sorted node ids,
## canonicalized edge pairs, fixed 6-decimal floats). TWO TIERS, so a review
## diff stays readable (an earlier version of this fixture ran the full
## detail format at each preset's authored node_count — 800 — and produced a
## ~10,000-line diff on any legitimate procgen change, which is a guard
## nobody reads):
##   - DETAIL tier, [constant _DETAIL_NODE_COUNT] nodes: the full NODE / MOD /
##     ADDON / AMOD / SPELL / KEYSTONE format below, byte-for-byte. This is
##     what names the field and the node when something breaks — a mis-wired
##     `budget_policy` or a dropped `addon_policy` shows up identically at 80
##     nodes and at 800, so more nodes here buys nothing for a FIELD
##     migration, only more lines to not read.
##   - DIGEST tier, each preset's own AUTHORED node_count (800): one
##     `DIGEST_SHA256` line, hashing the exact same canonical text this script
##     would otherwise have written at full scale. This is what still covers
##     the genuinely scale-sensitive paths the small graph can't exercise —
##     per-N blocker counts, the budget curve, the phased draw's aggregate
##     shape. A DIGEST_SHA256 mismatch means generation changed at full scale
##     ONLY (the DETAIL tier still matched) — the fix is to regenerate locally
##     and diff the full text by hand to see what moved, never to weaken this
##     assert to make it pass.
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
## unresolved-seed sentinel). Sharing one seed across both presets (and both
## tiers) is fine: each preset's own shape_mask / archetypes / pools diverge
## the RNG stream immediately.
const _SEED := 424242

## Node count for the DETAIL tier (see the class docstring). Both presets
## carry 6 archetypes (`archetypes` array) and every `guaranteed_placements`
## entry targets a specific node regardless of density (KeystonePlacement's
## nearest-to-point, MinNearStartingPoints' per-starter neighbourhood,
## RandomBudgetBoost's own `count`) — none of that needs scale to appear.
## Checked empirically at 80 (`_REGENERATE`, then grepped the result): every
## archetype, several ADDON/AMOD blocks, at least one SPELL grant, and the
## KEYSTONE line all show up for both presets. Go up only if a future preset
## adds a path that 80 nodes doesn't reach — and say in a comment here why,
## same as this one.
const _DETAIL_NODE_COUNT := 80

## See the docstring above. Never flip this to make a failing comparison
## pass — that defeats the entire point of a characterization test.
const _REGENERATE := false


## `node_count <= 0` (the default) leaves the preset's own AUTHORED node_count
## in place — the DIGEST tier's whole point is exercising generation at the
## scale the preset actually ships at.
func _fresh_config(preset_path: String, node_count: int = -1) -> GraphProcgenConfig:
	# generate() mutates the config in place (mask size_for, the propagated
	# outer_radius) and load() is cached, so every pass needs its own copy.
	var cfg: GraphProcgenConfig = (load(preset_path) as GraphProcgenConfig).duplicate(true)
	cfg.seed = _SEED
	if node_count > 0:
		# #349: `topology` is a top-level module `.tres` (ExtResource), so the
		# `duplicate(true)` above did NOT deep-copy it — only embedded
		# SubResources cross that boundary. Without re-duplicating here, this
		# DETAIL-tier override would mutate the SAME cached Topology resource
		# that `_run_preset`'s very next `_fresh_config(preset_path)` call (no
		# override, for the DIGEST tier) reads — silently overwriting the
		# "authored node_count" it depends on. Same trap as #349 acceptance 4,
		# one call site over.
		cfg.topology = cfg.topology.duplicate(true)
		cfg.topology.node_count = node_count
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


## Sorted by (stat_id, operation) rather than left in draw/aggregation order:
## after `_roll_modifiers_v4`'s fuse step those pairs are unique per node, so
## this reorder is content-only and can't hide a real value regression behind
## a harmless change to internal draw order. Shared by [member
## SkillNode.modifiers] (MOD) and each addon's `local_modifiers` (AMOD) — same
## shape, different line tag, so a diff always says which system moved.
static func _mod_lines(tag: String, indent: String, mods_in: Array[StatModifier]) -> PackedStringArray:
	var mods := mods_in.duplicate()
	mods.sort_custom(func(a: StatModifier, b: StatModifier) -> bool:
		if a.stat_id != b.stat_id:
			return String(a.stat_id) < String(b.stat_id)
		return a.operation < b.operation)
	var lines := PackedStringArray()
	for m in mods:
		# Procgen-drawn modifiers are plain static rolls (no formula) today,
		# but capture it anyway rather than silently dropping a field a future
		# pool entry might set.
		var formula_tag := "-"
		if m.formula != null:
			formula_tag = JSON.stringify(m.formula.to_dict(), "", true)
		lines.append("%s%s %s %d %s %d %s" % [
			indent, tag, String(m.stat_id), m.operation, _fmt_float(m.value), m.priority, formula_tag,
		])
	return lines


## An addon instance carries no `id` of its own (that lives on the
## [AddonPoolEntry] resource, one layer up, never on the minted node) — but
## `PackedScene.instantiate()` stamps the root's `scene_file_path` back to the
## source scene, so the scene's own file name is a stable, human-readable
## stand-in. Falls back to the script path for the (untested-in-practice) case
## of an addon minted without a backing scene.
static func _addon_identity(a: SkillNodeAddon) -> String:
	var path := a.scene_file_path
	if path.is_empty() and a.get_script() != null:
		path = (a.get_script() as Script).resource_path
	return path.get_file().get_basename() if not path.is_empty() else "<unknown>"


## One node's canonical text block:
##   NODE <id> <x> <y> <archetype>
##     MOD ...                          — [member SkillNode.modifiers]
##     ADDON <identity>                 — one per [method SkillNode.get_addons]
##       AMOD ...                       — that addon's local_modifiers
##     SPELL <spell id>                 — one per SpellGrant in [member SkillNode.effects]
##     KEYSTONE <keystone id>           — only if [member SkillNode.keystone] is stamped
## ADDON blocks sort by identity (ties broken by attach order, since a
## non-unique addon can repeat) so a reordering of `_roll_and_attach_addons`'s
## internal draw loop can't produce a false diff either.
static func _node_block(id: int, node: SkillNode) -> String:
	var arch_id := String(node.archetype.id) if node.archetype != null else ""
	var lines := PackedStringArray()
	lines.append("NODE %d %s %s %s" % [
		id, _fmt_float(node.position.x), _fmt_float(node.position.y), arch_id,
	])
	lines.append_array(_mod_lines("MOD", "  ", node.modifiers))

	var addons: Array[SkillNodeAddon] = node.get_addons()
	var addon_order: Array[int] = []
	for i in addons.size():
		addon_order.append(i)
	addon_order.sort_custom(func(i: int, j: int) -> bool:
		var id_i := _addon_identity(addons[i])
		var id_j := _addon_identity(addons[j])
		if id_i != id_j:
			return id_i < id_j
		return i < j)
	for i in addon_order:
		var a := addons[i]
		lines.append("  ADDON %s" % _addon_identity(a))
		lines.append_array(_mod_lines("AMOD", "    ", a.local_modifiers))

	# Spell grants land as plain SpellGrant effects appended directly to
	# `effects` by GraphProcgenSpellGrants._place (via SkillNode.add_effect) —
	# distinct from a keystone's own effects, which live on the keystone
	# resource, not here. SpellDef is authored content, so its `id` is a
	# stable, resolvable identity (same reasoning as the archetype id above).
	var spell_ids: Array[String] = []
	for e in node.effects:
		if e is SpellGrant and (e as SpellGrant).spell_def != null:
			spell_ids.append(String((e as SpellGrant).spell_def.id))
	spell_ids.sort()
	for sid in spell_ids:
		lines.append("  SPELL %s" % sid)

	# Keystone.stamp() sets node.keystone and (params permitting) overrides
	# base_type_color / base_radius / mints addon_scenes — the last of those
	# is already covered above since it lands through the same get_addons()
	# walk. What ISN'T implied by anything else here is the keystone's own
	# identity and its live-referenced effects grant, so capture the
	# identity (its resource path is as stable and resolvable as a SpellDef
	# id) and skip the presentation overrides as cosmetic.
	if node.keystone != null:
		var kpath: String = node.keystone.resource_path
		var kid := kpath.get_file().get_basename() if not kpath.is_empty() else "<unnamed>"
		lines.append("  KEYSTONE %s" % kid)

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


## SEED / NODE_COUNT / NODE.../EDGE.../STARTER... only — no comment prose, no
## DIGEST_* lines. This is the exact text the DIGEST tier hashes, and it's
## deliberately free of anything but generation-derived content: if the
## comment header lived in here too, editing this script's docstrings would
## silently change every committed hash with no change to GraphProcgen at
## all. [method _render_text] wraps this with the header for the committed
## fixture; the DIGEST tier calls this directly and hashes the result.
static func _canonical_data_text(data: Dictionary) -> String:
	var out := PackedStringArray()
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


## The committed-fixture text: prose header, DIGEST_* lines (the DETAIL-tier
## `data` this is always called with carries the DIGEST fields merged in —
## see [method _run_preset]), then [method _canonical_data_text].
static func _render_text(preset_path: String, data: Dictionary) -> String:
	var out := PackedStringArray()
	out.append("# GOLDEN FIXTURE for %s" % preset_path)
	out.append("# Generated by test/unit/procgen/test_preset_generation_golden.gd — DO NOT hand-edit.")
	out.append("# Characterizes GraphProcgen.generate()'s output for #349's config/module migration to")
	out.append("# be judged against, captured from master BEFORE that migration touched procgen/**. See")
	out.append("# `gh issue view 349 --comments` (acceptance 3 & 6).")
	out.append("#")
	out.append("# TWO TIERS — see the DETAIL / DIGEST comment at the top of the test script. NODE blocks")
	out.append("# below are the DETAIL tier only (_DETAIL_NODE_COUNT nodes); DIGEST_SHA256 hashes the same")
	out.append("# canonical text (SEED/NODE_COUNT/NODE.../EDGE.../STARTER..., no comments, no DIGEST_*")
	out.append("# lines) at the preset's own authored (full-scale) node_count, unwritten here.")
	out.append("#")
	out.append("# Regenerating this file is a DELIBERATE act, never a way to turn a red test green: flip")
	out.append("# `_REGENERATE` in the test script (or run `mise run procgen-golden-regenerate`), rerun the")
	out.append("# script alone, flip `_REGENERATE` back, and justify WHY generation was supposed to change")
	out.append("# in the commit message.")
	if data.has("digest_sha256"):
		out.append("DIGEST_NODE_COUNT %d" % int(data.digest_node_count))
		out.append("DIGEST_SEED %d" % int(data.digest_seed))
		out.append("DIGEST_SHA256 %s" % String(data.digest_sha256))
	out.append(_canonical_data_text(data))
	return "\n".join(out)


## Inverse of [method _render_text] / [method _build_snapshot] — parses a
## committed fixture back into the same snapshot shape. No lambda-closure
## helper here on purpose (see `.claude/rules/gdscript-pitfalls.md` /
## project memory on lambda-captures-by-value): the flush-current-node step is
## inlined at both places it's needed rather than factored into a Callable
## that would close over a stale copy of `current_id` / `current_lines`.
static func _parse_fixture(text: String) -> Dictionary:
	var seed_val := 0
	var node_count := 0
	var digest_node_count := 0
	var digest_seed := 0
	var digest_sha256 := ""
	var nodes: Dictionary[int, String] = {}
	var edges: Array[Vector2i] = []
	var starters: Array[int] = []

	var current_id := -1
	var current_lines := PackedStringArray()

	for raw_line in text.split("\n"):
		if raw_line.strip_edges().is_empty() or raw_line.begins_with("#"):
			continue
		# Any indented line (MOD, ADDON, AMOD, SPELL, KEYSTONE) belongs to the
		# NODE block currently accumulating — only SEED / NODE_COUNT /
		# DIGEST_* / NODE / EDGE / STARTER start at column 0.
		if raw_line.begins_with(" "):
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
			"DIGEST_NODE_COUNT":
				digest_node_count = int(parts[1])
			"DIGEST_SEED":
				digest_seed = int(parts[1])
			"DIGEST_SHA256":
				digest_sha256 = parts[1]
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
		"digest_node_count": digest_node_count,
		"digest_seed": digest_seed,
		"digest_sha256": digest_sha256,
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


## DETAIL-tier comparison: per-node, not a whole-blob diff — a corrupted value
## must name which preset AND which node in the failure message (#349's
## acceptance 3).
func _assert_detail_matches(preset_key: String, golden: Dictionary, actual: Dictionary) -> void:
	assert_eq(int(actual.seed), int(golden.seed),
		"%s: fixture's SEED header doesn't match _SEED — was the fixture hand-edited?" % preset_key)
	assert_eq(int(actual.node_count), int(golden.node_count),
		"%s: detail-tier node count differs from golden (%d vs %d) — did _DETAIL_NODE_COUNT change "
		% [preset_key, actual.node_count, golden.node_count]
		+ "without a regenerate?")

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


## DIGEST-tier comparison: one hash, so the failure message is the whole
## story — a mismatch here means generation changed at full scale ONLY (the
## DETAIL tier above already matched, or this wouldn't be the only failure).
## Regenerate locally and diff the full text by hand to see what moved;
## weakening this to something fuzzier defeats the tier's entire purpose.
func _assert_digest_matches(preset_key: String, golden: Dictionary, actual: Dictionary) -> void:
	assert_eq(int(actual.digest_node_count), int(golden.digest_node_count),
		"%s: digest-tier node count differs from golden (%d vs %d) — does the preset's authored "
		% [preset_key, actual.digest_node_count, golden.digest_node_count]
		+ "node_count still match what was last committed?")
	assert_eq(String(actual.digest_sha256), String(golden.digest_sha256),
		("%s: full-scale (N=%d) generation hash differs from golden, but the %d-node DETAIL tier "
		+ "still matched — this is a change visible ONLY at full scale (per-N blocker counts, the "
		+ "budget curve, the phased draw's aggregate shape). Regenerate locally and diff the full "
		+ "text by hand to see what moved; do not weaken this assert to make it pass.")
		% [preset_key, actual.digest_node_count, _DETAIL_NODE_COUNT])


func _run_preset(preset_key: String) -> void:
	var preset_path: String = _PRESETS[preset_key]

	var detail_cfg := _fresh_config(preset_path, _DETAIL_NODE_COUNT)
	var detail_gen := await _generate(detail_cfg)
	var detail_snapshot := _build_snapshot(detail_cfg, detail_gen.graph, detail_gen.result)

	# Authored (full-scale) node_count — no override.
	var full_cfg := _fresh_config(preset_path)
	var full_gen := await _generate(full_cfg)
	var full_snapshot := _build_snapshot(full_cfg, full_gen.graph, full_gen.result)
	var full_hash := _canonical_data_text(full_snapshot).sha256_text()

	var combined := detail_snapshot.duplicate()
	combined["digest_node_count"] = full_snapshot.node_count
	combined["digest_seed"] = full_cfg.seed
	combined["digest_sha256"] = full_hash

	if _REGENERATE:
		_write_fixture(preset_key, preset_path, combined)
		fail_test(
			"_REGENERATE is true — rewrote %s.golden.txt. Flip _REGENERATE back to false, "
			% preset_key
			+ "re-run to confirm green, and commit the fixture with a message justifying WHY "
			+ "generation was supposed to change.")
		return

	var golden := _load_fixture(preset_key)
	_assert_detail_matches(preset_key, golden, combined)
	_assert_digest_matches(preset_key, golden, combined)

	# Acceptance 2: repeat generate() in-process, same seeds, for BOTH tiers —
	# a fixture that is flaky by construction (unstable sort, an unseeded
	# roll) is worse than none, and that can differ by scale.
	var detail_cfg_b := _fresh_config(preset_path, _DETAIL_NODE_COUNT)
	var detail_gen_b := await _generate(detail_cfg_b)
	var detail_snapshot_b := _build_snapshot(detail_cfg_b, detail_gen_b.graph, detail_gen_b.result)
	assert_eq(_canonical_data_text(detail_snapshot_b), _canonical_data_text(detail_snapshot),
		"%s: repeat DETAIL-tier generate() produced different output — ordering nondeterminism"
		% preset_key)

	var full_cfg_b := _fresh_config(preset_path)
	var full_gen_b := await _generate(full_cfg_b)
	var full_snapshot_b := _build_snapshot(full_cfg_b, full_gen_b.graph, full_gen_b.result)
	var full_hash_b := _canonical_data_text(full_snapshot_b).sha256_text()
	assert_eq(full_hash_b, full_hash,
		"%s: repeat DIGEST-tier (N=%d) generate() produced a different hash — ordering nondeterminism"
		% [preset_key, full_snapshot.node_count])


func test_first_level_matches_golden() -> void:
	await _run_preset("first_level")


func test_coop_versus_matches_golden() -> void:
	await _run_preset("coop_versus")
