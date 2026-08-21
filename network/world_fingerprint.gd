class_name WorldFingerprint
extends RefCounted

## A cheap "do two peers hold the same world?" checksum, for the multiplayer
## harness.
##
## It hashes exactly what the wave-0 command vocabulary can change: which
## [SkillNode] (by [member SkillNode.stable_id]) is owned by which [Entity] (by
## [member Entity.entity_id]). Not HP, not stats — a fingerprint that changes
## for reasons the harness cannot yet sync is a fingerprint nobody reads.
##
## [b]Why this exists at all.[/b] Node ids mint LAZILY, and every node in a
## hand-authored scene reads `0` until something forces a topology rebuild — so
## a command carrying `0` resolves to nothing, silently
## (`.claude/rules/multiplayer-sync.md`). Reading every id through
## [method Graph.get_stable_id] here both forces the mint and turns a silent
## id disagreement into a visible mismatch at link-up.


## Order-independent (ids are sorted first), so two peers that built the same
## graph in a different child order still agree — they shouldn't, but a
## fingerprint that also fails on that is diagnosing two things at once.
static func compute(graph: Graph) -> int:
	if graph == null:
		return 0
	var rows: Array[Vector2i] = []
	for node in graph.get_skill_nodes():
		var owner_id := 0
		if node.owned_by != null:
			owner_id = node.owned_by.entity_id
		rows.append(Vector2i(graph.get_stable_id(node), owner_id))
	rows.sort()
	# Folded by hand (FNV-1a) rather than via `Array.hash()`: this number is
	# compared ACROSS PROCESSES, so it must not depend on engine hashing
	# internals that are free to differ between builds.
	var h := 2166136261
	for row in rows:
		h = ((h ^ row.x) * 16777619) & 0x7FFFFFFF
		h = ((h ^ row.y) * 16777619) & 0x7FFFFFFF
	return h


## One line for a human: node count, owned count, fingerprint. What the harness
## logs on both peers so a mismatch says *how* they differ, not just that they do.
static func describe(graph: Graph) -> String:
	if graph == null:
		return "no graph"
	var nodes := graph.get_skill_nodes()
	var owned := 0
	for node in nodes:
		if node.owned_by != null:
			owned += 1
	return "%d nodes, %d owned, fp %d" % [nodes.size(), owned, compute(graph)]
