class_name WorldFingerprint
extends RefCounted

## A cheap "do two peers hold the same world?" checksum, for the multiplayer
## harness AND #527's join handshake.
##
## Folds four tiers ([GraphSnapshot]'s own tier table): ownership, topology (node identity +
## edges), ACCUMULATED per-node state — stake level, allocation level,
## regen stacks, and node HP — and per-node STATUSES (#879: `(id, power)`
## pairs, see [method _status_rows]). It does NOT fold derived [StatBoard] totals: the
## tier table says totals never cross the wire, so folding them would assert
## agreement on a quantity the sync layer deliberately does not transmit — a
## fingerprint that can fail for reasons the sync layer cannot cause is a
## fingerprint nobody reads.
##
## [b]HP folds QUANTIZED to int[/b] (`roundi(hp * 100)`), never as a raw float.
## [member PoolStat.current] is a float, and this number is compared ACROSS
## PROCESSES — folding a float through FNV-1a would make the fold depend on
## engine/platform float-formatting internals that are free to differ between
## builds, exactly the trap this file warned about before HP was foldable at
## all. HP is in the fold anyway: without it, a cast that kills nothing and a
## cast that never ran produce the same number.
##
## [b]One [method compute], not two fingerprints.[/b] A component breakdown is
## surfaced through [method describe] for diagnostics only — a mismatch there
## says *how* two peers differ, not just that they do — but the number peers
## actually compare is the single fold below.
##
## [b]Why this exists at all.[/b] Node ids mint LAZILY, and every node in a
## hand-authored scene reads `0` until something forces a topology rebuild — so
## a command carrying `0` resolves to nothing, silently
## (`.claude/rules/multiplayer-sync.md`). Reading every id through
## [method Graph.get_stable_id] here both forces the mint and turns a silent
## id disagreement into a visible mismatch at link-up.

## Folded by hand (FNV-1a) rather than via `Array.hash()`: this number is
## compared ACROSS PROCESSES, so it must not depend on engine hashing
## internals that are free to differ between builds. `rows` is sorted first
## (order-independent — two peers that built the same graph in a different
## child order still agree; a fingerprint that fails on that too would be
## diagnosing two things at once) and each row is itself an `Array[int]`.
static func _fold_rows(rows: Array) -> int:
	rows.sort()
	var h := 2166136261
	for row in rows:
		for v in row:
			h = ((h ^ int(v)) * 16777619) & 0x7FFFFFFF
	return h


## Node identity + who owns it. `[stable_id, owner_entity_id]` per node (0 =
## unowned).
static func _ownership_rows(graph: Graph) -> Array:
	var rows: Array = []
	for node in graph.get_skill_nodes():
		var owner_id := 0
		if node.owned_by != null:
			owner_id = node.owned_by.entity_id
		rows.append([graph.get_stable_id(node), owner_id])
	return rows


## Graph structure: one row per edge, endpoints order-normalized so an edge
## authored `(A, B)` on one peer and `(B, A)` on another still folds the same.
static func _topology_rows(graph: Graph) -> Array:
	var rows: Array = []
	for edge in graph.get_edges():
		var a := graph.get_stable_id(edge.from)
		var b := graph.get_stable_id(edge.to)
		rows.append([mini(a, b), maxi(a, b)])
	return rows


## Accumulated per-node state: stake level, allocation level, regen stacks,
## and HP (quantized — see class docstring).
static func _accumulated_rows(graph: Graph) -> Array:
	var rows: Array = []
	for node in graph.get_skill_nodes():
		var hp_int := roundi(node.get_current_hp() * 100.0)
		rows.append([graph.get_stable_id(node), node.stake_level,
				node.allocation_level, node.regen_stacks, hp_int])
	return rows


## One row per node holding ≥ 1 status (#879 — omitted entirely otherwise, so
## the common case adds nothing to fold): `[stable_id, id_hash_0, power_0,
## id_hash_1, power_1, …]`, PAIRS SORTED BY STATUS ID first — so two peers
## holding the same statuses in different application order still fold equal
## (this is what makes it safe to fold as one variable-length row instead of
## one row per status, unlike the fixed-shape rows above). `power` quantizes
## the same way HP does (`roundi(power * 100)`, see the class docstring) —
## a raw float would make the fold depend on engine float-formatting.
static func _status_rows(graph: Graph) -> Array:
	var rows: Array = []
	for node in graph.get_skill_nodes():
		var pairs: Array = []
		for s in node.get_combat().get_statuses():
			pairs.append([String(s.def.id), roundi(s.power * 100.0)])
		if pairs.is_empty():
			continue
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var row: Array = [graph.get_stable_id(node)]
		for pair in pairs:
			row.append(String(pair[0]).hash())
			row.append(pair[1])
		rows.append(row)
	return rows


static func compute(graph: Graph) -> int:
	if graph == null:
		return 0
	var rows := _ownership_rows(graph) + _topology_rows(graph) + _accumulated_rows(graph) + _status_rows(graph)
	return _fold_rows(rows)


## One line for a human: node count, owned count, the fingerprint peers
## actually compare, PLUS a per-tier breakdown so a mismatch says *how* the
## two worlds differ (ownership vs topology vs accumulated state) rather than
## just that they do. The breakdown is diagnostic only — see class docstring.
static func describe(graph: Graph) -> String:
	if graph == null:
		return "no graph"
	var nodes := graph.get_skill_nodes()
	var owned := 0
	for node in nodes:
		if node.owned_by != null:
			owned += 1
	return "%d nodes, %d owned, fp %d (own %d / topo %d / accum %d / status %d)" % [
		nodes.size(), owned, compute(graph),
		_fold_rows(_ownership_rows(graph)),
		_fold_rows(_topology_rows(graph)),
		_fold_rows(_accumulated_rows(graph)),
		_fold_rows(_status_rows(graph)),
	]
