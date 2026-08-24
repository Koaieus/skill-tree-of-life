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


## Decode a payload built by [method encode] into [param graph] — a RECONCILE,
## not a rebuild (#561 D6). A node whose `stable_id` is already present is
## updated in place; only a genuinely-new id mints a [SkillNode], only a
## genuinely-absent one is removed, and the same holds edge-by-edge.
##
## [b]Decoding into a POPULATED graph is therefore safe, and that is the
## resync backstop's whole contract[/b] (#561; the join case is just the
## degenerate one where the graph starts empty and every row is new). The
## alternative D6 offered — tear the world down and replay — was rejected
## against what #560 had since built: [method StatBoard.read_dict] reconciles
## rather than wipes precisely so a live entity's `initialize()` signal wiring
## survives a resync, and freeing every [SkillNode] would strand every
## [EffectInstance] `source_node` and every [Navigator] mirror that a repair
## has no business disturbing. A repair that touches nothing when nothing
## drifted is also what keeps a resync silent (#561 acceptance 6).
##
## [b]The existing id index is built ONCE, up front, and every lookup below
## reads it rather than [method Graph.get_by_stable_id].[/b] Not a
## micro-optimization: every `add_skill_node` marks the graph's topology dirty,
## so a per-row lookup through the graph would rebuild the whole index once per
## row — an O(nodes^2) decode at the 2000-node scale this payload exists for,
## the exact shape `.claude/rules/graph.md` says this repo has shipped twice.
static func decode(bytes: PackedByteArray, graph: Graph) -> void:
	var payload := _unpack(bytes)
	var res: Array = payload.get("res", [])
	var existing: Dictionary[int, SkillNode] = {}
	var stale: Dictionary[int, SkillNode] = {}
	for node in graph.get_skill_nodes():
		var id := graph.get_stable_id(node)
		existing[id] = node
		stale[id] = node
	var edges_before := _edge_index(graph)
	var by_id: Dictionary[int, SkillNode] = {}
	for row in (payload.get("nodes", []) as Array):
		var node := _decode_node(graph, row as Array, res, existing)
		var id := int((row as Array)[_R_STABLE_ID])
		by_id[id] = node
		existing[id] = node
		stale.erase(id)
	# Every node the payload did NOT name is gone from the authority's world, so
	# it goes from this one. The join path never reaches this — an empty graph
	# has nothing stale — it exists for the resync (#561 gap 1, nodes half).
	for node in stale.values():
		graph.remove_skill_node(node)
	_reconcile_edges(graph, payload.get("edges", []) as Array, by_id, edges_before)


## `{Vector2i(lo_id, hi_id): Array[Edge]}` for the graph as it stands — an
## ARRAY per key, not one [Edge]: a procgen graph really does carry parallel
## edges and self-loops between the same pair, and
## [method WorldFingerprint._topology_rows] folds one row per [Edge], so
## collapsing them would make a decoded graph disagree with the graph it was
## decoded from. Read before any node is added or removed, for the same
## index-invalidation reason [method decode] builds its node map up front.
static func _edge_index(graph: Graph) -> Dictionary:
	var out: Dictionary[Vector2i, Array] = {}
	for edge in graph.get_edges():
		var a := graph.get_stable_id(edge.from)
		var b := graph.get_stable_id(edge.to)
		var key := Vector2i(mini(a, b), maxi(a, b))
		if not out.has(key):
			out[key] = []
		out[key].append(edge)
	return out


## Edges reconcile as a MULTISET keyed by endpoint pair, order-normalized the
## way [method WorldFingerprint._topology_rows] normalizes them. For each pair,
## as many existing [Edge]s as the payload wants are left strictly alone (their
## render slots survive a repair), any surplus is removed, and any shortfall is
## created.
static func _reconcile_edges(
	graph: Graph, pairs: Array, by_id: Dictionary, edges_before: Dictionary
) -> void:
	var wanted: Dictionary[Vector2i, int] = {}
	for pair in pairs:
		var a := int((pair as Array)[0])
		var b := int((pair as Array)[1])
		if by_id.has(a) and by_id.has(b):
			var key := Vector2i(mini(a, b), maxi(a, b))
			wanted[key] = wanted.get(key, 0) + 1
	for key in edges_before:
		# A node removal above already took its edges with it, so only an edge
		# whose endpoints both SURVIVED is still ours to reconcile.
		if not (by_id.has(key.x) and by_id.has(key.y)):
			continue
		var have: Array = edges_before[key]
		for i in range(wanted.get(key, 0), have.size()):
			graph.remove_edge(have[i])
	for key in wanted:
		var have_count: int = (edges_before[key] as Array).size() if edges_before.has(key) else 0
		for _i in maxi(0, wanted[key] - have_count):
			graph.add_edge(by_id[key.x], by_id[key.y])


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


## Reconcile-or-mint (#561 D6). Everything below either matches what the node
## already holds and is left strictly alone, or is a delta — so a resync into a
## world that never drifted is a walk, not a rebuild.
static func _decode_node(
	graph: Graph, row: Array, res: Array, existing: Dictionary
) -> SkillNode:
	var stable_id := int(row[_R_STABLE_ID])
	var node: SkillNode = existing.get(stable_id)
	if node == null:
		node = _NODE_SCENE.instantiate() as SkillNode
		# The authored tier lands BEFORE `add_skill_node`, as it always has: a
		# [SkillNode]'s `_ready` reads its archetype.
		_reconcile_authored(node, row, res)
		node.position = Vector2(float(row[_R_X]), float(row[_R_Y]))
		graph.add_skill_node(node)
		graph.restore_stable_id(node, stable_id)
	else:
		_reconcile_authored(node, row, res)
		node.position = Vector2(float(row[_R_X]), float(row[_R_Y]))
	# Stake before allocation: allocation is a fill WITHIN the stake cap.
	node.stake_level = int(row[_R_STAKE])
	node.allocation_level = int(row[_R_ALLOC])
	node.regen_stacks = int(row[_R_REGEN])
	var owner_id := int(row[_R_OWNER_ID])
	# Assigned unconditionally, null included: on a resync the authority saying
	# "unowned" has to be able to UNSET an owner this peer wrongly believes in.
	node.owned_by = graph.get_by_entity_id(owner_id) if owner_id != 0 else null
	_reconcile_addons(node, row, res)
	# Addons attach (and push their own modifiers) above — the node's OWN
	# residual modifiers reconcile on top, reproducing the source's full list.
	_reconcile_modifiers(node, row)
	node.restore_current_hp(float(row[_R_HP]) / 100.0)
	return node


## The authored tier, assigned only where it actually differs — a redundant
## write would churn a [SkillNode] setter (and its visuals) on every resync.
static func _reconcile_authored(node: SkillNode, row: Array, res: Array) -> void:
	var archetype := _interned(res, int(row[_R_ARCHETYPE])) as Archetype
	if node.archetype != archetype:
		node.archetype = archetype
	var keystone := _interned(res, int(row[_R_KEYSTONE])) as Keystone
	if node.keystone != keystone:
		node.keystone = keystone
	var effects: Array[Effect] = []
	for effect_idx in (row[_R_EFFECTS] as Array):
		var e := _interned(res, int(effect_idx)) as Effect
		if e != null:
			effects.append(e)
	if node.effects != effects:
		node.effects = effects


static func _interned(res: Array, idx: int) -> Resource:
	if idx < 0 or idx >= res.size():
		return null
	return load(String(res[idx]))


## Addons are compared as the ordered list of scene paths [method _encode_node]
## wrote. Equal means untouched; otherwise the whole set is detached and
## re-instantiated, which is honest — an addon carries behaviour and its own
## modifier ledger, so a positional patch would be the half-clever merge D6
## warned about. `remove_child` is what deregisters it (`_detach_addon` hangs
## off `child_exiting_tree`), so its modifiers come off with it.
static func _reconcile_addons(node: SkillNode, row: Array, res: Array) -> void:
	var wanted: Array[String] = []
	for addon_idx in (row[_R_ADDONS] as Array):
		wanted.append(String(res[int(addon_idx)]))
	var current: Array[String] = []
	for addon in node.get_addons():
		current.append(addon.scene_file_path)
	if current == wanted:
		return
	for addon in node.get_addons():
		node.remove_child(addon)
		addon.queue_free()
	for path in wanted:
		var scene := load(path) as PackedScene
		if scene != null:
			node.add_child(scene.instantiate())


## The node's own (non-addon-sourced) entity-scoped modifiers, matched to the
## incoming rows BY WIRE FORM and kept in place when they match.
##
## [b]Keeping the instance is the point, not an optimization.[/b]
## [method SkillNode.remove_entity_modifiers_from] strips the owner's board BY
## IDENTITY, so a resync that minted fresh objects for modifiers that never
## changed would leave the board holding handles no later deallocate can find —
## the node-level twin of the stale-handle trap `stats_system/stat.gd`
## documents for [EffectInstance].
##
## Deltas go through [method SkillNode.add_entity_modifier] /
## [method SkillNode.remove_entity_modifier] rather than touching
## [member SkillNode.modifiers] directly, so an OWNED node's board moves with
## it; ownership is assigned above, before this runs.
static func _reconcile_modifiers(node: SkillNode, row: Array) -> void:
	var addon_mod_ids: Dictionary[int, bool] = {}
	for addon in node.get_addons():
		for m in addon.entity_modifiers:
			addon_mod_ids[m.get_instance_id()] = true
		for m in addon.get_local_modifiers():
			addon_mod_ids[m.get_instance_id()] = true
	var residual: Array[StatModifier] = []
	for m in node.modifiers:
		if not addon_mod_ids.has(m.get_instance_id()):
			residual.append(m)
	for mod_dict in (row[_R_MODS] as Array):
		var matched := -1
		for i in residual.size():
			if residual[i].to_dict() == mod_dict:
				matched = i
				break
		if matched >= 0:
			residual.remove_at(matched)
			continue
		var m := StatModifierCodec.from_dict(mod_dict)
		if m != null:
			node.add_entity_modifier(m)
	# Whatever the payload did not account for is drift, and comes off.
	for m in residual:
		node.remove_entity_modifier(m)


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
