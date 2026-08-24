class_name GraphSnapshot
extends RefCounted

## Encoder/decoder for #527's "a joining client receives a serialized graph;
## it does not regenerate one" contract. Procgen is deterministic, but
## serializing also covers the cases regenerating can't: mid-run join,
## hand-authored levels, and (later) save/load. See
## #527's acceptance spec, and #463's 2026-08-24 sync-model decision comment.
##
## [b]Three tiers, split per-moment not per-system[/b] (the issue's own
## table):
## - Authored (archetype, addon placements, KEYSTONES — named explicitly in
##   #527's Decisions section, plus node-direct `effects` by the same
##   reasoning) crosses as an INTERNED REF into a resource-path table built
##   once per snapshot. 7 archetypes / 6 addon scenes repeated per-node as full
##   paths is the single biggest lever the issue's arithmetic calls out —
##   ~230 KB of repeated strings collapses to a handful of bytes plus a
##   once-sent table. A keystone or effect built via `.new()` rather than
##   loaded from a shared `.tres` (real gameplay content never does this —
##   only tests) has no `resource_path` and is silently dropped rather than
##   crossing broken; that mirrors how `_encode_node` already treats an
##   addon with no `scene_file_path`.
## - Accumulated (owner, HP, stake/allocation level, regen stacks, the
##   modifier LIST) crosses BY VALUE — no formula rederives history.
## - Derived ([StatBoard] totals, aura contributions, vision/fog) never
##   crosses. Not this class's problem at all.
##
## [b]An addon's own modifiers are NOT double-encoded.[/b] Re-instantiating an
## addon's `.tscn` on decode re-attaches its `entity_modifiers` /
## `local_modifiers` for free (`.claude/rules/skill-node-addons.md` —
## attaching is just `add_child`). So [method _encode_node] strips any
## modifier on [member SkillNode.modifiers] that's also present on one of the
## node's attached addons before encoding it, and [method _decode_node]
## attaches addons FIRST, then appends the residual (the node's own "offered"
## modifiers) on top — reproducing the same list the source node had.
##
## [b]Rows are POSITIONAL[/b] (arrays, not dictionaries with string keys) —
## string keys like `allocation_level` roughly double a naive payload's size,
## per the issue's own measurement. The whole structure goes through
## `var_to_bytes` then `PackedByteArray.compress(COMPRESSION_ZSTD)` before it
## leaves this class — wire time on LAN is 1-7ms either way, so this is a
## tidiness requirement, not a performance one, but paths-per-node would have
## been the embarrassing omission.
##
## [b]Ownership resolves through the RECEIVING graph's own entities.[/b] An
## owner id with no matching [Entity] (via [method Graph.get_by_entity_id])
## decodes as unowned — spawning entities and minting their ids is #528's
## concern (`RunConfig` / `ParticipantRoster`), not this unit's. A mid-run join
## is expected to land its roster before (or alongside) its graph snapshot.

## Node row indices — so `_encode_node`/`_decode_node` don't repeat magic
## numbers, and a positional row still self-documents at the call site.
const _R_STABLE_ID := 0
const _R_ARCHETYPE := 1  ## index into `res`, -1 for none
const _R_OWNER_ID := 2   ## Entity.entity_id, 0 for unowned
const _R_X := 3
const _R_Y := 4
const _R_STAKE := 5
const _R_ALLOC := 6
const _R_REGEN := 7
const _R_HP := 8      ## roundi(current_hp * 100) — see WorldFingerprint's own note on why HP quantizes
const _R_MODS := 9    ## Array of StatModifierCodec dicts — the node's own residual (non-addon-sourced) modifiers
const _R_ADDONS := 10 ## Array[int], indices into `res`, one per attached addon in child order
const _R_KEYSTONE := 11 ## index into `res`, -1 for none — SkillNode.keystone
const _R_EFFECTS := 12  ## Array[int], indices into `res` — SkillNode.effects (direct grants, independent of a keystone)


## Builds the payload for the WHOLE graph in one shot: `res` (the interned
## resource-path table), `nodes` (positional rows, see the `_R_*` consts), and
## `edges` (`[from_stable_id, to_stable_id]` pairs). Callers that want to send
## progress in chunks should slice `graph.get_skill_nodes()` themselves and
## call [method encode_nodes] per slice, sharing one [_InternTable] across
## slices — this method exists for the common case (and every unit test).
static func encode(graph: Graph) -> PackedByteArray:
	var table := _InternTable.new()
	var nodes: Array = []
	for node in graph.get_skill_nodes():
		nodes.append(_encode_node(graph, node, table))
	var edges: Array = []
	for edge in graph.get_edges():
		edges.append([graph.get_stable_id(edge.from), graph.get_stable_id(edge.to)])
	return _pack({"res": table.paths, "nodes": nodes, "edges": edges})


## Decode a payload built by [method encode] into [param graph]. Builds fresh
## [SkillNode]s with the SAME `stable_id`s the source had
## ([method Graph.restore_stable_id]) and the same edges. Safe to call into an
## empty graph (the join case) or a populated one, as long as the stable ids
## don't collide — decoding twice into the same graph is not this method's
## contract to make safe.
static func decode(bytes: PackedByteArray, graph: Graph) -> void:
	var payload := _unpack(bytes)
	var res: Array = payload.get("res", [])
	var by_id: Dictionary[int, SkillNode] = {}
	for row in (payload.get("nodes", []) as Array):
		var node := _decode_node(graph, row as Array, res)
		by_id[node.stable_id] = node
	for pair in (payload.get("edges", []) as Array):
		var a: SkillNode = by_id.get(int((pair as Array)[0]))
		var b: SkillNode = by_id.get(int((pair as Array)[1]))
		if a != null and b != null:
			graph.add_edge(a, b)


## Bytes-per-node at the CURRENT graph size, for the size guard the issue
## asks for (measure small-N and extrapolate rather than generating 2000
## nodes inside the unit suite). Excludes the once-sent `res` table, which is
## the whole point of interning — it shouldn't be amortized into a per-node
## number that then looks node-count-proportional when it isn't.
static func bytes_per_node(graph: Graph) -> float:
	var node_count := graph.get_skill_nodes().size()
	if node_count == 0:
		return 0.0
	var table := _InternTable.new()
	var nodes: Array = []
	for node in graph.get_skill_nodes():
		nodes.append(_encode_node(graph, node, table))
	var bytes := _pack({"nodes": nodes})
	return float(bytes.size()) / float(node_count)


## ZSTD in this engine build has no dynamic (size-less) decompression —
## `decompress_dynamic` throws "only supported with gzip, DEFLATE, and
## Brotli" — so the uncompressed size has to ride along as a 4-byte
## little-endian header the decoder reads before calling
## `PackedByteArray.decompress`, which DOES need it up front.
static func _pack(payload: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(payload)
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, raw.size())
	return header + compressed


static func _unpack(bytes: PackedByteArray) -> Dictionary:
	var raw_size := bytes.decode_u32(0)
	var compressed := bytes.slice(4)
	var raw := compressed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	return bytes_to_var(raw) as Dictionary


static func _encode_node(graph: Graph, node: SkillNode, table: _InternTable) -> Array:
	var archetype_idx := -1
	if node.archetype != null:
		archetype_idx = table.intern(node.archetype.resource_path)
	var owner_id := 0
	if node.owned_by != null:
		owner_id = node.owned_by.entity_id
	var addon_idx: Array = []
	var addon_mod_ids: Dictionary[int, bool] = {}
	for addon in node.get_addons():
		if addon.scene_file_path != "":
			addon_idx.append(table.intern(addon.scene_file_path))
		for m in addon.entity_modifiers:
			addon_mod_ids[m.get_instance_id()] = true
		for m in addon.get_local_modifiers():
			addon_mod_ids[m.get_instance_id()] = true
	var residual: Array = []
	for m in node.modifiers:
		if not addon_mod_ids.has(m.get_instance_id()):
			residual.append(m.to_dict())
	var keystone_idx := -1
	if node.keystone != null and node.keystone.resource_path != "":
		keystone_idx = table.intern(node.keystone.resource_path)
	var effect_idx: Array = []
	for e in node.effects:
		if e != null and e.resource_path != "":
			effect_idx.append(table.intern(e.resource_path))
	var row: Array
	row.resize(13)
	row[_R_STABLE_ID] = graph.get_stable_id(node)
	row[_R_ARCHETYPE] = archetype_idx
	row[_R_OWNER_ID] = owner_id
	row[_R_X] = node.position.x
	row[_R_Y] = node.position.y
	row[_R_STAKE] = node.stake_level
	row[_R_ALLOC] = node.allocation_level
	row[_R_REGEN] = node.regen_stacks
	row[_R_HP] = roundi(node.get_current_hp() * 100.0)
	row[_R_MODS] = residual
	row[_R_ADDONS] = addon_idx
	row[_R_KEYSTONE] = keystone_idx
	row[_R_EFFECTS] = effect_idx
	return row


static func _decode_node(graph: Graph, row: Array, res: Array) -> SkillNode:
	var node := _NODE_SCENE.instantiate() as SkillNode
	var archetype_idx := int(row[_R_ARCHETYPE])
	if archetype_idx >= 0:
		node.archetype = load(String(res[archetype_idx])) as Archetype
	var keystone_idx := int(row[_R_KEYSTONE])
	if keystone_idx >= 0:
		node.keystone = load(String(res[keystone_idx])) as Keystone
	var effects: Array[Effect] = []
	for effect_idx in (row[_R_EFFECTS] as Array):
		var e := load(String(res[int(effect_idx)])) as Effect
		if e != null:
			effects.append(e)
	node.effects = effects
	node.position = Vector2(float(row[_R_X]), float(row[_R_Y]))
	graph.add_skill_node(node)
	graph.restore_stable_id(node, int(row[_R_STABLE_ID]))
	# Stake before allocation: allocation is a fill WITHIN the stake cap.
	node.stake_level = int(row[_R_STAKE])
	node.allocation_level = int(row[_R_ALLOC])
	node.regen_stacks = int(row[_R_REGEN])
	var owner_id := int(row[_R_OWNER_ID])
	if owner_id != 0:
		node.owned_by = graph.get_by_entity_id(owner_id)
	for addon_idx in (row[_R_ADDONS] as Array):
		var scene := load(String(res[int(addon_idx)])) as PackedScene
		node.add_child(scene.instantiate())
	# Addons attach (and push their own modifiers) above — append the node's
	# OWN residual modifiers on top, reproducing the source's full list.
	for mod_dict in (row[_R_MODS] as Array):
		var m := StatModifierCodec.from_dict(mod_dict)
		if m != null:
			node.modifiers.append(m)
	node.restore_current_hp(float(row[_R_HP]) / 100.0)
	return node


const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


## Per-snapshot resource interning: a `Resource.resource_path` (or a
## `PackedScene`'s, for addons) -> a stable index into `paths`, built lazily
## as nodes are visited. Not a global registry — the whole graph's distinct
## resources rarely number more than a few dozen, and a per-snapshot table
## needs no coordination with anything else that might load resources.
class _InternTable:
	var paths: Array[String] = []
	var _index: Dictionary[String, int] = {}

	func intern(path: String) -> int:
		if _index.has(path):
			return _index[path]
		var idx := paths.size()
		paths.append(path)
		_index[path] = idx
		return idx
