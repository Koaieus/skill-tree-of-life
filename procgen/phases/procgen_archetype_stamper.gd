@tool
class_name ProcgenArchetypeStamper
extends RefCounted

## Stage 4 of [method GraphProcgen.generate] (hub #422, child 3), extracted
## from `graph_procgen.gd` with its body unchanged: archetype assignment
## (target-driven BFS-grow) plus the post-clustering territory-stamp pass.
## Static and stateless — the caller owns the RNG and hands it in, and this
## phase never touches the progress callback. Same seed → byte-identical graph
## is guarded by `test/integration/procgen/test_procgen_golden.gd`.
## See the clustering section of docs/domain/procgen.md.


## One int per position, indexing into [GraphProcgenContent.archetypes], or
## -1 where the node carries no archetype. With no authored archetypes every
## node stays unassigned before the stamps run; with no authored stamps the
## BFS-grow result is returned unchanged.
static func run(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> PackedInt32Array:
	var type_assignments: PackedInt32Array
	if not config.content.archetypes.is_empty():
		type_assignments = _assign_archetypes(positions, edge_pairs, config, rng)
	else:
		# No archetypes → no clustering source. Leave every node unassigned;
		# the per-node loop skips content for a -1 assignment.
		type_assignments.resize(positions.size())
		type_assignments.fill(-1)

	# Post-clustering territory stamps. Override archetype assignments
	# for nodes inside each stamp's region — before building the placement
	# context so the updated assignments flow into guaranteed placements too.
	if not config.content.archetype_stamps.is_empty():
		_apply_archetype_stamps(positions, edge_pairs, type_assignments, config)
	return type_assignments


## Cluster assignment. Returns an int per position, indexing into
## [GraphProcgenContent.archetypes]. Algorithm (BFS-grow; see the clustering
## section of docs/domain/procgen.md):
##  1. Compute target node count per archetype from target_ratio shares.
##  2. Per archetype, sample cluster sizes from cluster_size_weights until
##     Σ sizes ≥ target_count. Build a flat plan list.
##  3. Sort plans largest-first so big clusters claim space first.
##  4. Place each plan's seed greedily (random first seed, then
##     farthest-from-existing-seeds among unclaimed nodes).
##  5. BFS-grow each cluster through the pruned graph adjacency up to its
##     target_size, claiming only unclaimed neighbours.
##  6. Any unclaimed leftovers: graph-BFS outward until a claimed neighbour
##     is found, inherit its archetype.
##  7. Per-node cluster_jitter reroll using the assigned archetype's policy.
static func _assign_archetypes(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> PackedInt32Array:
	var n := positions.size()
	var out := PackedInt32Array()
	out.resize(n)
	for i in n:
		out[i] = -1
	if n == 0 or config.content.archetypes.is_empty():
		return out

	# Step 1: target counts per archetype (normalised target_ratio).
	var total_ratio := 0.0
	for a in config.content.archetypes:
		if a != null:
			total_ratio += maxf(0.0, a.target_ratio)
	if total_ratio <= 0.0:
		# All-zero: uniform fallback.
		for k in config.content.archetypes.size():
			if config.content.archetypes[k] != null:
				total_ratio += 1.0
	var target_counts: Array[int] = []
	target_counts.resize(config.content.archetypes.size())
	var assigned_so_far := 0
	for k in config.content.archetypes.size():
		var policy: ArchetypePolicy = config.content.archetypes[k]
		var ratio := 0.0 if policy == null else maxf(0.0, policy.target_ratio)
		if total_ratio > 0.0 and ratio == 0.0 and policy != null:
			ratio = 1.0  # uniform-fallback path
		var tc := int(round(float(n) * ratio / total_ratio)) if total_ratio > 0.0 else 0
		target_counts[k] = tc
		assigned_so_far += tc
	# Reconcile rounding so Σ target_counts == n (drop / add to the largest).
	var diff := n - assigned_so_far
	if diff != 0:
		var biggest_idx := 0
		for k in target_counts.size():
			if target_counts[k] > target_counts[biggest_idx]:
				biggest_idx = k
		target_counts[biggest_idx] = maxi(0, target_counts[biggest_idx] + diff)

	# Step 2: build flat cluster plan list.
	# Each plan = {archetype_idx, target_size}. Use Vector2i (x=archetype, y=size).
	var plans: Array[Vector2i] = []
	for k in config.content.archetypes.size():
		var policy: ArchetypePolicy = config.content.archetypes[k]
		if policy == null:
			continue
		var remaining := target_counts[k]
		while remaining > 0:
			var size := policy.sample_cluster_size(rng)
			size = mini(size, remaining)
			if size <= 0:
				break
			plans.append(Vector2i(k, size))
			remaining -= size

	# Step 3: sort plans largest-first.
	plans.sort_custom(func(a, b): return a.y > b.y)

	# Adjacency from pruned edges.
	var adj: Array[PackedInt32Array] = []
	for i in n:
		adj.append(PackedInt32Array())
	for e in edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)

	# Steps 4–5: place seed, then BFS-grow each plan.
	var seeds: Array[int] = []
	for plan in plans:
		var seed_idx := _pick_seed_node(positions, out, seeds, rng)
		if seed_idx < 0:
			break  # no unclaimed nodes left
		out[seed_idx] = plan.x
		seeds.append(seed_idx)
		# BFS-grow from this seed up to plan.y nodes.
		var claimed := 1
		var frontier: Array[int] = [seed_idx]
		while claimed < plan.y and not frontier.is_empty():
			var next_frontier: Array[int] = []
			for node in frontier:
				for nb in adj[node]:
					if out[nb] != -1:
						continue
					out[nb] = plan.x
					next_frontier.append(nb)
					claimed += 1
					if claimed >= plan.y:
						break
				if claimed >= plan.y:
					break
			frontier = next_frontier

	# Step 6: fallback for unclaimed nodes — graph-BFS to nearest claimed.
	# (Running counts maintained so ArchetypeBalancer, if enabled, can react.)
	var counts := PackedInt32Array()
	counts.resize(config.content.archetypes.size())
	var total_assigned := 0
	for i in n:
		if out[i] != -1 and out[i] < counts.size():
			counts[out[i]] += 1
			total_assigned += 1
	var balancer: ArchetypeBalancer = config.content.archetype_balancer
	var use_balancer := balancer != null and balancer.enabled
	for i in n:
		if out[i] != -1:
			continue
		var found := _bfs_to_first_claimed(i, out, adj)
		if found != -1:
			out[i] = found
		else:
			# Disconnected & nothing claimed reachable.
			out[i] = (balancer.pick(config.content.archetypes, counts, total_assigned, rng)
					if use_balancer else _pick_archetype_by_ratio(config.content.archetypes, rng))
		if out[i] >= 0 and out[i] < counts.size():
			counts[out[i]] += 1
			total_assigned += 1

	# Step 7: cluster_jitter reroll per archetype.
	for i in n:
		var policy: ArchetypePolicy = config.content.archetypes[out[i]] if out[i] >= 0 and out[i] < config.content.archetypes.size() else null
		if policy != null and rng.randf() < policy.cluster_jitter:
			var prev := out[i]
			out[i] = (balancer.pick(config.content.archetypes, counts, total_assigned, rng)
					if use_balancer else _pick_archetype_by_ratio(config.content.archetypes, rng))
			if use_balancer and prev != out[i]:
				if prev >= 0 and prev < counts.size():
					counts[prev] -= 1
				if out[i] >= 0 and out[i] < counts.size():
					counts[out[i]] += 1

	return out


static func _pick_seed_node(
		positions: Array[Vector2],
		assignments: PackedInt32Array,
		existing_seeds: Array[int],
		rng: RandomNumberGenerator,
) -> int:
	# Greedy farthest-from-existing-seeds among unclaimed. First seed is random.
	var n := positions.size()
	if existing_seeds.is_empty():
		# Random unclaimed.
		var unclaimed: Array[int] = []
		for i in n:
			if assignments[i] == -1:
				unclaimed.append(i)
		if unclaimed.is_empty():
			return -1
		return unclaimed[rng.randi() % unclaimed.size()]
	var best_idx := -1
	var best_min_sq := -1.0
	for i in n:
		if assignments[i] != -1:
			continue
		var min_sq := INF
		for s in existing_seeds:
			var d := positions[i].distance_squared_to(positions[s])
			if d < min_sq:
				min_sq = d
		if min_sq > best_min_sq:
			best_min_sq = min_sq
			best_idx = i
	return best_idx


static func _bfs_to_first_claimed(
		start: int,
		assignments: PackedInt32Array,
		adj: Array[PackedInt32Array],
) -> int:
	# Returns the archetype index of the first claimed node reachable from
	# `start` via BFS, or -1 if none.
	var seen := {}
	seen[start] = true
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for nb in adj[current]:
			if seen.has(nb):
				continue
			seen[nb] = true
			if assignments[nb] != -1:
				return assignments[nb]
			queue.append(nb)
	return -1


static func _pick_archetype_by_ratio(
		archetypes: Array[ArchetypePolicy],
		rng: RandomNumberGenerator,
) -> int:
	var total := 0.0
	for a in archetypes:
		if a != null:
			total += maxf(0.0, a.target_ratio)
	if total <= 0.0:
		return rng.randi() % archetypes.size()
	var r := rng.randf() * total
	for k in archetypes.size():
		var a := archetypes[k]
		if a == null:
			continue
		r -= maxf(0.0, a.target_ratio)
		if r <= 0.0:
			return k
	return archetypes.size() - 1


# ── Territory stamping ─────────────────────────────────────────────


static func _apply_archetype_stamps(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		type_assignments: PackedInt32Array,
		config: GraphProcgenConfig,
) -> void:
	var n := positions.size()
	for stamp in config.content.archetype_stamps:
		if stamp == null:
			continue
		if stamp.archetype_idx < 0 or stamp.archetype_idx >= config.content.archetypes.size():
			push_warning("ArchetypeStamp: archetype_idx %d out of range (archetypes has %d entries); skipping."
				% [stamp.archetype_idx, config.content.archetypes.size()])
			continue

		match stamp.mode:
			ArchetypeStamp.RegionMode.EUCLIDEAN:
				var rsq := stamp.radius * stamp.radius
				if rsq <= 0.0:
					continue
				for i in n:
					if positions[i].distance_squared_to(stamp.position) <= rsq:
						type_assignments[i] = stamp.archetype_idx

			ArchetypeStamp.RegionMode.TOPOLOGICAL:
				if stamp.seed_node_index < 0 or stamp.seed_node_index >= n:
					push_warning("ArchetypeStamp: seed_node_index %d out of range (0..%d); skipping."
						% [stamp.seed_node_index, n - 1])
					continue
				var indices := _region_indices_from_hops(stamp.seed_node_index, stamp.max_hops, edge_pairs, n)
				for i in indices:
					type_assignments[i] = stamp.archetype_idx


## BFS flood: returns all node indices reachable from [param start] in at most
## [param max_hops] hops (including [param start] itself). Uses [param edge_pairs]
## to build the adjacency list lazily. Shared by [method _apply_archetype_stamps]
## (stamp region) and available for any future non-PlacementContext BFS needs.
static func _region_indices_from_hops(
		start: int,
		max_hops: int,
		edge_pairs: Array[Vector2i],
		node_count: int,
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if start < 0 or start >= node_count or max_hops < 0:
		return out
	var adj: Array[PackedInt32Array] = []
	for i in node_count:
		adj.append(PackedInt32Array())
	for e in edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	var seen := {start: true}
	var frontier: Array[int] = [start]
	out.append(start)
	var hops := 0
	while hops < max_hops and not frontier.is_empty():
		var next: Array[int] = []
		for n_idx in frontier:
			for nb in adj[n_idx]:
				if seen.has(nb):
					continue
				seen[nb] = true
				next.append(nb)
				out.append(nb)
		frontier = next
		hops += 1
	return out
