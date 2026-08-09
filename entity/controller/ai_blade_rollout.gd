class_name AiBladeRollout
extends RefCounted

## Melee candidate rollout for AI v1 (#378 slice C). Ranged/magic candidates
## enumerate exhaustively ([AIController]'s `_gather_ranged_candidates` /
## `_gather_magic_candidates`); melee can't — the candidate space is every
## connected induced subgraph of the attacker's owned territory rooted at a
## pivot, up to `blade_size` members, and a full [method MeleeAttackPlan.resolve]
## (sim + physics-server hit scan) is milliseconds, not microseconds, per
## candidate (see the #378 melee-budget comment). This module bounds the
## search instead of enumerating it:
##
##   1. Free rejection — every owned node is a candidate PIVOT, but
##      [method _reach_bound] (BFS over owned territory, `blade_size` hops,
##      summed edge length — a real upper bound: PBD constraints keep edges
##      near rest length, so no swept particle can get farther than the sum
##      of edges along the path that reached it) rejects any pivot whose
##      farthest possible reach can't touch the nearest visible enemy, at
##      zero simulation cost. [method MeleeAttackPlan.build_drivers]'s arc
##      drivers sweep a full TAU regardless of swing_cw, so a directional test
##      collapses into this same distance check: there's no "wrong way" to
##      swing.
##   2. Steerable proposals — surviving pivots each grow ONE greedy chain of
##      blade members toward the visible-enemy centroid (closest-unselected-
##      neighbour-first), then every leaf-truncation of that chain becomes a
##      candidate. That's the "add/remove a leaf" local-search move from the
##      melee-budget comment, applied deterministically and boundedly rather
##      than as unbounded random walk. No UCB/bandit allocation across pivots:
##      the reach-bound in (1) is already a cheap admissible bound, and a
##      cheap bound is exactly the case where best-first search beats
##      rollout/bandit-style budget allocation (see the melee-budget comment's
##      "On MCMC vs. Monte Carlo" section) — so ranking every proposal once
##      and taking the top-K is the right amount of machinery, not a
##      shortcut.
##   3. Two-tier evaluation — every surviving proposal gets ONE coarse
##      [method BladeSim.simulate] pass (`dt`=1/30, 4 iterations — ~14x
##      cheaper than full fidelity) on [WorkerThreadPool] (simulate() is pure:
##      stateless over PackedVector2Array, no Node access, safe off-thread),
##      ranked by closest particle-to-enemy approach across the swing. Only
##      the top few finalists get a full-fidelity [method MeleeAttackPlan.resolve]
##      — the only place [BladeHitScan.scan] runs, and it ALWAYS runs here, on
##      the calling (main) thread inside [method gather_melee_candidates]'s
##      synchronous call stack, never inside a WorkerThreadPool task. That's
##      the #378 swarmify addendum's hard constraint: scan needs a live
##      [PhysicsDirectSpaceState2D] and isn't thread-safe.
##
## `thinned_nodes` fed into [method AiCombatScorer.score] is
## [member AttackOutcome.thinned_nodes] — actual blade vertices lost to a
## defensive-spike pop this swing ([BladePopResolver]), not blade_nodes.size().
## Merely selecting nodes for a blade doesn't wound them; only a pop does
## (see [constant AiCombatScorer._SHAPE_RISK_WEIGHT]'s "wound now, heals
## ~1/turn" doc) — so the risk term should read what the swing actually cost,
## not what it merely risked.

## Pivots kept after the free reach-bound rejection, nearest-to-an-enemy
## first — bounds proposal generation regardless of territory size.
const _MAX_PIVOTS := 6
## Blade sizes beyond this are not sane for v1's stat scaling; a guard
## against a pathological board making the chain-growth loop unbounded.
const _MAX_BLADE_SIZE_SAFETY := 16
## Finalists promoted to full-fidelity resolve + hit scan.
const _FINALIST_COUNT := 3
const _COARSE_DT := 1.0 / 30.0
const _COARSE_ITERS := 4


## Every melee candidate worth scoring this turn, already scored via
## [AiCombatScorer]. Empty if the entity has no owned territory, no visible
## enemy, or every pivot fails the reach-bound rejection.
static func gather_melee_candidates(
		entity: Entity, visible_enemies: Array[SkillNode], ai_tier: int) -> Array[AiCombatScorer.ScoredCandidate]:
	var out: Array[AiCombatScorer.ScoredCandidate] = []
	if entity == null or entity.navigator == null or visible_enemies.is_empty():
		return out
	var adjacency := _owned_adjacency(entity)
	if adjacency.is_empty():
		return out
	var enemy_positions: Array[Vector2] = []
	for e in visible_enemies:
		if e != null:
			enemy_positions.append(e.global_position)
	if enemy_positions.is_empty():
		return out
	var target_centroid := Vector2.ZERO
	for p in enemy_positions:
		target_centroid += p
	target_centroid /= enemy_positions.size()

	var pivot_infos := _prune_pivots(adjacency, enemy_positions)
	if pivot_infos.is_empty():
		return out

	var proposals := _propose_blade_selections(pivot_infos, adjacency, target_centroid)
	if proposals.is_empty():
		return out

	var finalists := _coarse_rank_and_select(proposals, entity, enemy_positions)
	for f in finalists:
		var pivot: SkillNode = f[0]
		var blade_nodes: Array[SkillNode] = f[1]
		var candidate := _resolve_and_score(entity, pivot, blade_nodes, visible_enemies, ai_tier)
		if candidate != null:
			out.append(candidate)
	return out


# ── Territory + free rejection ──────────────────────────────────────────────

## Owned SkillNode -> Array[SkillNode] of its neighbours that are ALSO owned
## by [param entity] — the walkable graph for blade pivot/member selection.
## Built off the cached [method Graph.get_neighbours] (O(degree) per node,
## see .claude/rules/graph.md), not a hand-rolled edge scan.
static func _owned_adjacency(entity: Entity) -> Dictionary:
	var out: Dictionary = {}
	if entity.navigator == null or entity.navigator.graph == null:
		return out
	var graph := entity.navigator.graph
	for n in entity.navigator.get_mirrored_nodes():
		var neighbours: Array[SkillNode] = []
		for nb in graph.get_neighbours(n):
			if nb != null and nb.owned_by == entity:
				neighbours.append(nb)
		out[n] = neighbours
	return out


## Every owned node with a nonzero blade_size whose reach bound reaches at
## least one visible enemy, nearest-enemy-distance-sorted and capped to
## [constant _MAX_PIVOTS]. Each entry is [pivot, max_size].
static func _prune_pivots(adjacency: Dictionary, enemy_positions: Array[Vector2]) -> Array:
	var candidates := []
	for pivot in adjacency.keys():
		var max_size := int((pivot as SkillNode).get_local_value(&"blade_size"))
		if max_size <= 0:
			continue
		max_size = mini(max_size, _MAX_BLADE_SIZE_SAFETY)
		var nearest := INF
		for p in enemy_positions:
			nearest = minf(nearest, (pivot as SkillNode).global_position.distance_to(p))
		var bound := _reach_bound(pivot, adjacency, max_size)
		if bound < nearest:
			continue # free rejection: this pivot can't possibly touch anyone visible
		candidates.append([pivot, max_size, nearest])
	candidates.sort_custom(func(a, b): return a[2] < b[2])
	if candidates.size() > _MAX_PIVOTS:
		candidates = candidates.slice(0, _MAX_PIVOTS)
	var out := []
	for c in candidates:
		out.append([c[0], c[1]])
	return out


## Largest cumulative edge-length path over owned territory from [param pivot],
## up to [param max_hops] hops — a genuine upper bound on swing reach (PBD
## distance constraints keep edges near rest length, so no particle can end
## up farther from the pivot than the sum of edges along the path that put it
## there). Explores every path, not just the first arrival at each node: two
## paths can reach the same node at the same hop count with different summed
## length in branchy territory, and only the longer one is a valid bound
## contributor. A node is re-queued whenever a strictly longer path to it is
## found, which terminates because distances only improve and are bounded by
## geometry + [param max_hops].
static func _reach_bound(pivot: SkillNode, adjacency: Dictionary, max_hops: int) -> float:
	if max_hops <= 0:
		return 0.0
	var best := 0.0
	var best_dist: Dictionary = {pivot: 0.0}
	var queue := [[pivot, 0.0, 0]]
	var head := 0
	while head < queue.size():
		var entry: Array = queue[head]
		head += 1
		var node: SkillNode = entry[0]
		var dist: float = entry[1]
		var hop: int = entry[2]
		if hop >= max_hops:
			continue
		for nb in adjacency.get(node, []):
			var nd: float = dist + node.global_position.distance_to((nb as SkillNode).global_position)
			if best_dist.has(nb) and best_dist[nb] >= nd:
				continue # an equal-or-better path here was already queued
			best_dist[nb] = nd
			best = maxf(best, nd)
			queue.append([nb, nd, hop + 1])
	return best


# ── Steerable proposals ──────────────────────────────────────────────────────

## For each surviving [pivot, max_size] pair, a greedy chain of blade members
## grown toward [param target_centroid] (closest-unselected-neighbour-first),
## then every leaf-truncation of that chain — the bounded "add/remove a leaf"
## move set. Each proposal is [pivot, Array[SkillNode] blade_nodes].
static func _propose_blade_selections(pivot_infos: Array, adjacency: Dictionary, target_centroid: Vector2) -> Array:
	var out := []
	for info in pivot_infos:
		var pivot: SkillNode = info[0]
		var max_size: int = info[1]
		var chain := _greedy_chain(pivot, adjacency, target_centroid, max_size)
		for l in range(1, chain.size() + 1):
			out.append([pivot, chain.slice(0, l)])
	return out


static func _greedy_chain(pivot: SkillNode, adjacency: Dictionary, target_pos: Vector2, max_size: int) -> Array[SkillNode]:
	var chain: Array[SkillNode] = []
	var selected: Dictionary = {pivot: true}
	for _i in max_size:
		var best: SkillNode = null
		var best_d := INF
		var seen: Dictionary = {}
		for n in selected.keys():
			for nb in adjacency.get(n, []):
				if selected.has(nb) or seen.has(nb):
					continue
				seen[nb] = true
				var d: float = (nb as SkillNode).global_position.distance_to(target_pos)
				if d < best_d:
					best_d = d
					best = nb
		if best == null:
			break
		chain.append(best)
		selected[best] = true
	return chain


# ── Two-tier evaluation ──────────────────────────────────────────────────────

## Coarse-simulates every proposal (threaded — [method BladeSim.simulate] is
## pure) and returns the top [constant _FINALIST_COUNT] by closest
## particle-to-enemy approach. Entries are [pivot, Array[SkillNode]].
static func _coarse_rank_and_select(proposals: Array, entity: Entity, enemy_positions: Array[Vector2]) -> Array:
	var scored := []
	# Build every BladeState/driver set on the CALLING thread (touches
	# SkillNode positions/stats) before handing pure data to worker tasks.
	var task_ids: Array[int] = []
	var task_targets := []
	for proposal in proposals:
		var pivot: SkillNode = proposal[0]
		var blade_nodes: Array[SkillNode] = proposal[1]
		var probe := MeleeAttackPlan.new()
		probe.attacker = entity
		probe.source = pivot
		probe.blade_nodes = blade_nodes
		var state := probe.build_blade_state()
		if state == null:
			continue
		var drivers := probe.build_drivers(state)
		var slot := [proposal, INF]
		scored.append(slot)
		var id := WorkerThreadPool.add_task(func() -> void:
			var traj := BladeSim.simulate(
					state, drivers, MeleeAttackPlan.SWING_DURATION, _COARSE_DT, _COARSE_ITERS)
			slot[1] = _closest_approach(traj, enemy_positions))
		task_ids.append(id)
	for id in task_ids:
		WorkerThreadPool.wait_for_task_completion(id)
	scored.sort_custom(func(a, b): return a[1] < b[1])
	var out := []
	for i in mini(_FINALIST_COUNT, scored.size()):
		out.append(scored[i][0])
	return out


static func _closest_approach(traj: BladeTrajectory, enemy_positions: Array[Vector2]) -> float:
	var best := INF
	for sample in traj.samples:
		for i in sample.size():
			for ep in enemy_positions:
				best = minf(best, sample[i].distance_to(ep))
	return best


# ── Full-fidelity resolve + scoring (main thread only) ──────────────────────

static func _resolve_and_score(
		entity: Entity, pivot: SkillNode, blade_nodes: Array[SkillNode],
		visible_enemies: Array[SkillNode], ai_tier: int) -> AiCombatScorer.ScoredCandidate:
	var plan := MeleeAttackPlan.new()
	plan.attacker = entity
	plan.source = pivot
	plan.blade_nodes = blade_nodes
	if not plan.is_valid():
		return null
	# The only call site that ever runs BladeHitScan.scan for AI candidate
	# generation — always here, on the calling thread, never inside a
	# WorkerThreadPool task (see the class doc's point 3).
	var outcome := plan.resolve()
	var primary := _primary_target(outcome, visible_enemies)
	if primary == null:
		return null
	var candidate := AiCombatScorer.score(
			BattleSystem.AttackMode.MELEE, outcome, primary, entity, ai_tier, outcome.thinned_nodes)
	candidate.source_node = pivot
	candidate.blade_nodes = blade_nodes
	return candidate


## The visible-hostile hit with the largest single damage instance — the
## candidate's kill/HP-comparison anchor for [AiCombatScorer]. A blade can hit
## several nodes at once; scoring still needs one representative target.
## Null if this swing didn't connect with anyone currently visible (a
## coarse-ranked candidate that missed on full-fidelity resolve).
static func _primary_target(outcome: AttackOutcome, visible_enemies: Array[SkillNode]) -> SkillNode:
	var enemy_set: Dictionary = {}
	for e in visible_enemies:
		enemy_set[e] = true
	var best: SkillNode = null
	var best_amount := -1.0
	for hit in outcome.hits:
		if hit.target == null or not enemy_set.has(hit.target):
			continue
		if hit.amount > best_amount:
			best_amount = hit.amount
			best = hit.target
	return best
