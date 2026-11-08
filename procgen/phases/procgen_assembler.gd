@tool
class_name ProcgenAssembler
extends RefCounted

## The final wiring of [method GraphProcgen.generate] (hub #422, child 5),
## extracted from `graph_procgen.gd` with its body unchanged: edges, the
## floor-guaranteed self-loop tiers, starting-node resolution and the blocker
## dict assembly. Static and stateless — [GraphProcgen] owns the main `rng`
## stream the tier draws ride, every progress emit and the return dict; this
## phase never touches the callback. Same seed → byte-identical graph is
## guarded by `test/integration/procgen/test_procgen_golden.gd`.
## See docs/domain/procgen.md.

## What [method run] hands back: the starting nodes (index-aligned with the
## caller's starters) and the blocker placements in draw order.
class Result extends RefCounted:
	var starting_nodes: Array[SkillNode] = []
	var blockers: Array[Dictionary] = []


## Wires `edge_pairs` then the self-loop tiers under `graph`, resolves the
## starting nodes and rebuilds the removable-blocker placements from the
## pre-loop index maps sampled by [ProcgenPlacement].
static func run(
		graph: Graph,
		nodes: Array[SkillNode],
		edge_pairs: Array[Vector2i],
		starter_count: int,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
		blocker_sizes: Dictionary,
		blocker_seeds: Dictionary,
		blocker_footprints: Dictionary,
		blocker_stakes: Dictionary,
		blocker_faces: Dictionary,
) -> Result:
	var out := Result.new()
	for pair in edge_pairs:
		graph.add_edge(nodes[pair.x], nodes[pair.y])

	# Self-loops — floor-guaranteed staged draw without replacement.
	# Tier 1 draws floor(N × p1) nodes uniformly from all generated nodes
	# (partial Fisher-Yates, no replacement); tier k draws floor(K_{k-1} × p_k)
	# from the previous tier's set. Each tier then does ONE Bernoulli on the
	# fractional remainder to add +1 (floor + 0-or-1), and a node that hits
	# tier k gets exactly k self-loops. The number of tier knobs IS the cap
	# (4) — raising it later means adding a tier-5 knob. Cores are NOT
	# excluded from the tier-1 pool — a self-loop on a core is a defining
	# launch condition by design.
	var tier_rates := [
			config.topology.self_loop_tier1_rate,
			config.topology.self_loop_tier2_rate,
			config.topology.self_loop_tier3_rate,
			config.topology.self_loop_tier4_rate,
	]
	var pool: Array = nodes.duplicate()
	for tier in tier_rates.size():
		var rate: float = tier_rates[tier]
		var count := int(floor(pool.size() * rate))
		if rng.randf() < pool.size() * rate - float(count):
			count += 1
		count = mini(count, pool.size())
		# Partial Fisher-Yates: the first `count` of the shuffled pool.
		for i in count:
			var j := i + rng.randi() % (pool.size() - i)
			var tmp: Variant = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		# Each tier UPGRADES its draw by one loop: a tier-1 node gets 1
		# self-loop, a tier-2 node 2 (1 from tier 1 + this), ... tier-k nodes
		# end with exactly k loops — add_edge is called k times total per
		# tier-k node across the cascade. Cap = 4 follows from 4 knobs.
		for i in count:
			var node := pool[i] as SkillNode
			graph.add_edge(node, node)
		pool = pool.slice(0, count)

	# Starting points were seeded first into Poisson; they occupy positions[0..n).
	for i in min(starter_count, nodes.size()):
		out.starting_nodes.append(nodes[i])

	# Removable-blocker placements, rebuilt from the index→size
	# map sampled before the per-node loop. `blocker_sizes` iterates in
	# insertion (tier) order — small, then medium, then large — matching the
	# old post-loop pass's result order, so result shape (`{node, size}`) is
	# unchanged.
	for idx: int in blocker_sizes:
		# The footprint crosses as NODES, not indices: `spawn_blocker` is
		# the consumer and it force-allocates them, so resolving here keeps the
		# index basis (which only `generate` can map) out of the level scene.
		var footprint: Array[SkillNode] = []
		for f: int in blocker_footprints.get(idx, PackedInt32Array()):
			footprint.append(nodes[f])
		out.blockers.append({
			"node": nodes[idx],
			"size": int(blocker_sizes[idx]),
			"prune_seed": int(blocker_seeds[idx]),
			"footprint": footprint,
			"stake_level": int(blocker_stakes.get(idx, 1)),
			"face": (blocker_faces.get(idx, {}) as Dictionary).get("face"),
			"face_seed": int((blocker_faces.get(idx, {}) as Dictionary).get("seed", 0)),
		})
	return out
