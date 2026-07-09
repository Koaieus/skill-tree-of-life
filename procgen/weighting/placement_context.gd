class_name PlacementContext
extends RefCounted

## Shared state passed to each [GuaranteedPlacement] in the pre-roll pass.
## Holds the post-topology / post-clustering plan that placements may inspect
## and mutate (role tags, future per-node forced-modifier hooks).

var positions: Array[Vector2] = []
var edge_pairs: Array[Vector2i] = []
## Per-node adjacency list (populated from `edge_pairs`).
var adjacency: Array[PackedInt32Array] = []
## Archetype index per node; indexes into either `config.archetypes` (v2) or
## `config.node_types` (v1). -1 if no archetype was assigned.
var type_assignments: PackedInt32Array = PackedInt32Array()
## Position indices of starting points (manual + random), in starter order.
var starter_indices: PackedInt32Array = PackedInt32Array()
## Per-node array of role tags. Each entry is an `Array[StringName]`. Tags
## here flow through to [BudgetPolicy.role_bonus] at modifier-roll time and
## are visible to future weight profiles.
var role_tags: Array = []
## Per-node [Keystone] reference (or null). Set by [KeystonePlacement];
## the per-node loop applies it via [method Keystone.stamp].
var keystones: Array = []
var rng: RandomNumberGenerator = null
var config: GraphProcgenConfig = null


func add_role_tag(node_index: int, tag: StringName) -> void:
	if node_index < 0 or node_index >= role_tags.size():
		return
	var tags: Array = role_tags[node_index]
	if tag not in tags:
		tags.append(tag)


func nodes_within_hops(start: int, max_hops: int) -> PackedInt32Array:
	# BFS — returns all node indices reachable from `start` in ≤ max_hops hops
	# (including `start` itself at hop 0).
	var out := PackedInt32Array()
	if start < 0 or start >= adjacency.size() or max_hops < 0:
		return out
	var seen := {start: true}
	var frontier: Array[int] = [start]
	out.append(start)
	var hops := 0
	while hops < max_hops and not frontier.is_empty():
		var next: Array[int] = []
		for n in frontier:
			for nb in adjacency[n]:
				if seen.has(nb):
					continue
				seen[nb] = true
				next.append(nb)
				out.append(nb)
		frontier = next
		hops += 1
	return out
