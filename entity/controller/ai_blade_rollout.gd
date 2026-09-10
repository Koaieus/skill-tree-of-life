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
##      collapses into this same distance check for REACH — a full sweep gets
##      to the same places either way. Direction still matters to the swing's
##      RESULT, though, and is a proposal dimension in (2) rather than a
##      pruning one.
##   2. Steerable proposals (#823 archetype generator) — surviving pivots each
##      grow ONE consecutive path outward toward the visible-enemy centroid
##      (closest-unselected-neighbour-of-the-tip-first, [method _grow_path]),
##      then [method _build_archetype] rigidifies a HANDLE consecutive from
##      the pivot (free where the joint is already triangulated or pre-
##      clamped, else a phantom [ClampAddon] weld, up to a tier-rolled target
##      length — D4) and spends whatever budget is left on a naive greedy
##      REACH extension (#824 refines the preference). A HANDFUL of proposals
##      per pivot, not an enumeration: this archetype plus at most one shorter
##      reach variant, in both swing directions — bounded independent of
##      `blade_size`, which is what makes #824's cap lift (16 -> 64)
##      affordable. See `.claude/rules/blade-budget-and-clamps.md`. No UCB/
##      bandit allocation across pivots: the reach-bound in (1) is already a
##      cheap admissible bound, and a cheap bound is exactly the case where
##      best-first search beats rollout/bandit-style budget allocation (see
##      the melee-budget comment's "On MCMC vs. Monte Carlo" section) — so
##      ranking every proposal once and taking the top-K is the right amount
##      of machinery, not a shortcut.
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
## `popped_nodes` fed into [method AiCombatScorer.score] is
## [member AttackOutcome.popped_nodes] — blade vertices a defensive spike
## actually destroyed this swing ([BladePopResolver]), not blade_nodes.size()
## and not the wider set of vertices a pop severed (#799).
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
## D4's tier ladder tops out here — t3 -> handle target 3-4. Clamped
## defensively so an out-of-range `ai_tier` can't silently exceed the
## authored ladder.
const _MAX_AI_TIER := 3
## Finalists promoted to full-fidelity resolve + hit scan.
const _FINALIST_COUNT := 3
const _COARSE_DT := 1.0 / 30.0
const _COARSE_ITERS := 4


## Every melee candidate worth scoring this turn, already scored via
## [AiCombatScorer]. Empty if the entity has no owned territory, no visible
## enemy, or every pivot fails the reach-bound rejection.
static func gather_melee_candidates(
		entity: Entity, visible_enemies: Array[SkillNode], ai_tier: int,
		rng: RandomNumberGenerator = null) -> Array[AiCombatScorer.ScoredCandidate]:
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

	var proposals := _propose_blade_selections(
			pivot_infos, adjacency, target_centroid, ai_tier, rng)
	if proposals.is_empty():
		return out

	var finalists := _coarse_rank_and_select(proposals, entity, enemy_positions)
	for f in finalists:
		var pivot: SkillNode = f[0]
		var blade_nodes: Array[SkillNode] = f[1]
		var clamp_nodes: Array[SkillNode] = f[3]
		var candidate := _resolve_and_score(
				entity, pivot, blade_nodes, f[2], visible_enemies, ai_tier, clamp_nodes)
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

## Fallback for a caller that doesn't care which handle the AI rolls (most
## unit fixtures probing geometry/direction/scoring, not tier behaviour) —
## deterministic, never [method RandomNumberGenerator.randomize]. Production
## always passes [member AIController.rng]; this exists so a 3-arg
## [method gather_melee_candidates] call (most of this file's own test suite,
## and #822's swing-direction fixture) keeps compiling and reproducible
## without threading a seed through every call site.
static func _default_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return r


## #823 — the archetype generator. For each surviving [pivot, max_size] pair:
## a single consecutive-from-pivot [b]handle[/b] (rigidify first, budget rule
## not a selection bias — see [method _build_archetype]) plus whatever budget
## is left spent on a naive greedy [b]reach[/b] extension (child #824 refines
## the preference; this issue only has to not enumerate). Each pivot then
## contributes a [b]handful[/b] of proposals, not every leaf-truncation of a
## chain — a hard bound (#823 requirement 1): [method _build_archetype]'s
## single (members, clamps) result, plus (when the tail has a plain,
## unclamped member to drop) one shorter variant, [b]in both swing
## directions[/b] — at most 4 proposals per pivot regardless of `max_size`,
## which is what keeps #824's cap lift (16 -> 64) affordable. Each proposal is
## [pivot, Array[SkillNode] blade_nodes, bool swing_cw, Array[SkillNode] clamp_nodes].
##
## [b]Direction is part of a candidate's IDENTITY, not a choice made after
## picking one[/b] (#692 follow-up). It used to be neither: every AI swing ran
## at [member MeleeAttackPlan.swing_cw]'s `false` default, so half the move set
## was unreachable. Two things make it matter, and only the second is obvious:
##
##   - The blade is a PBD chain, so it LAGS its driver — reversing the sweep
##     traces a genuinely different path, not the same circle backwards.
##     Measured on a 2-member chain against an off-axis enemy, the coarse
##     metric below reads 0.048 one way and 9.210 the other. (A single rigid
##     arm really is symmetric: 7.371861 vs 7.371915. So this buys nothing for
##     a 1-member blade, and a great deal for anything longer.)
##   - Order of contact decides what a defensive spike costs. A pop kills the
##     vertex and severs everything downstream from that instant
##     ([BladePopResolver]), so sweeping into a spiked hemisphere FIRST can
##     zero a swing the other direction would have banked — the owner's #537
##     report.
##
## Nothing here estimates either effect. Both directions simply enter the same
## ranking and the same gate-accurate finalist resolve, which is what keeps
## this a wider search rather than a second scoring path (#537 D4).
static func _propose_blade_selections(
		pivot_infos: Array, adjacency: Dictionary, target_centroid: Vector2,
		ai_tier: int = 1, rng: RandomNumberGenerator = null) -> Array:
	var actual_rng := rng if rng != null else _default_rng()
	var out := []
	for info in pivot_infos:
		var pivot: SkillNode = info[0]
		var max_size: int = info[1]
		if max_size <= 0:
			continue
		# D4: target handle length = randi_range(tier, tier + 1), tier maxed
		# at 3 (t0 -> 0-1 ... t3 -> 3-4) — the ONE place rigidity-seeking
		# lives (#771 hub, owner 2026-09-10: "0-1 means sometimes no clamping
		# attempt at all, just flop... all rigidity-seeking lives in the
		# tier-ladder... accidental truss, all good").
		var tier := clampi(ai_tier, 0, _MAX_AI_TIER)
		var handle_target := actual_rng.randi_range(tier, tier + 1)
		var archetype := _build_archetype(pivot, adjacency, target_centroid, max_size, handle_target)
		var members: Array[SkillNode] = archetype.members
		if members.is_empty():
			continue
		var clamps: Array[SkillNode] = archetype.clamps
		var variants: Array = [[members, clamps]]
		# A second, shorter variant — the bounded echo of the old "add/remove
		# a leaf" local search — ONLY when the tail member is plain reach, not
		# part of the handle: dropping a clamped node would silently change
		# the handle this proposal claims to have, not just its reach.
		if members.size() > 1 and not clamps.has(members[-1]):
			var shorter: Array[SkillNode] = members.slice(0, members.size() - 1)
			variants.append([shorter, clamps])
		for v in variants:
			for cw in [false, true]:
				out.append([pivot, v[0], cw, v[1]])
	return out


## The two-step archetype (#771 hub D1) for one pivot: rigidify a handle
## consecutive from the pivot outward, THEN spend whatever budget remains on a
## naive greedy reach extension. Single pass, budget-correct by construction —
## `spent` never exceeds `max_size`, the ONE budget shared between members and
## clamps (`.claude/rules/blade-budget-and-clamps.md`). Returns
## {members: Array[SkillNode], clamps: Array[SkillNode] (subset of members)}.
##
## [b]Member selection is unconditionally geometric — [method _grow_path]
## decides `path` before this function ever runs.[/b] Requirement 3 is a
## BUDGET rule, not a selection bias: free rigidity (an already-triangulated
## joint, or one already carrying a procgen [ClampAddon]) is taken when the
## walk happens to pass through it, never hunted for. A tier-0 blade that
## comes out rigid over already-triangulated territory does so by accident,
## exactly as the owner specified.
static func _build_archetype(
		pivot: SkillNode, adjacency: Dictionary, target_centroid: Vector2,
		max_size: int, handle_target: int) -> Dictionary:
	var path := _grow_path(pivot, adjacency, target_centroid, max_size)
	# Triangulation is checked against the FULL candidate path up front, not
	# incrementally as `members` grows — `members` ends up an exact PREFIX of
	# `path` (both phases below only ever consume `path` in order, never
	# skip), so a path node's real graph neighbours are the right set to ask
	# "already triangulated" against even before this walk has reached them.
	# Checking only nodes-added-so-far would miss the ordinary case: the
	# THIRD vertex of a Pivot-C-N1 triangle is N1, one step further out than
	# the joint C being asked about.
	var full_selection: Array[SkillNode] = [pivot]
	full_selection.append_array(path)
	var edges := _induced_edges_index(full_selection, adjacency)
	var members: Array[SkillNode] = []
	var clamps: Array[SkillNode] = []
	var spent := 0
	var rigidified := 0
	var handle_open := true
	var i := 0
	while i < path.size() and handle_open and rigidified < handle_target and spent < max_size:
		var node: SkillNode = path[i]
		members.append(node)
		spent += 1
		var particle_idx := i + 1 # pivot occupies index 0, path[k] -> k + 1
		if BladeState.edges_form_triangle_at(edges, particle_idx) or node.has_addon(ClampAddon):
			rigidified += 1 # free — costs nothing, still extends the RIGID handle
		elif spent < max_size and node.can_attach_addon(ClampAddon):
			clamps.append(node)
			spent += 1
			rigidified += 1
		else:
			# #771 D2: a gap here (no budget, or the slot's already full) means
			# nothing further out ever compounds — stop rigidifying. `node`
			# stays a plain member; it was already paid for above.
			handle_open = false
		i += 1
	# Reach extension — naive greedy, exactly the walk order [method
	# _grow_path] already produced. #824 refines the preference (spiked
	# nodes, distance from core); this issue only owns "don't enumerate".
	while i < path.size() and spent < max_size:
		members.append(path[i])
		spent += 1
		i += 1
	return {members = members, clamps = clamps}


## A single consecutive walk outward from [param pivot] toward [param
## target_pos] (closest-unselected-neighbour-of-the-TIP-first) — a genuine
## PATH, unlike the retired `_greedy_chain` which grew from the whole selected
## set and so could branch into a star/tree. The "handle" mechanic (#771 D2)
## is specifically about CONSECUTIVE-from-pivot joints, which only means
## something over a real path.
static func _grow_path(pivot: SkillNode, adjacency: Dictionary, target_pos: Vector2, max_len: int) -> Array[SkillNode]:
	var path: Array[SkillNode] = []
	var selected: Dictionary = {pivot: true}
	var tip: SkillNode = pivot
	for _i in max_len:
		var best: SkillNode = null
		var best_d := INF
		for nb in adjacency.get(tip, []):
			if selected.has(nb):
				continue
			var d: float = (nb as SkillNode).global_position.distance_to(target_pos)
			if d < best_d:
				best_d = d
				best = nb
		if best == null:
			break
		path.append(best)
		selected[best] = true
		tip = best
	return path


## [param selection]'s own induced edges as an index-mapped [Array[Vector2i]]
## over `selection`'s own order (so `selection[0]` — always the pivot, by
## every caller's convention — is particle index 0), read off [param
## adjacency] (owned-territory SkillNode -> SkillNode, i.e. exactly what
## [method _owned_adjacency] hands the whole generator). Same shape as
## [member BladeState.edges], so [method BladeState.edges_form_triangle_at]
## works identically on either — one triangle-detection implementation, not a
## topology-time copy and a BladeState-time copy (`.claude/rules/degree.md`).
static func _induced_edges_index(selection: Array[SkillNode], adjacency: Dictionary) -> Array[Vector2i]:
	var idx: Dictionary = {}
	for i in selection.size():
		idx[selection[i]] = i
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	for node in selection:
		var a: int = idx[node]
		for nb in adjacency.get(node, []):
			if not idx.has(nb):
				continue
			var b: int = idx[nb]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(key):
				continue
			seen[key] = true
			out.append(key)
	return out


# ── Two-tier evaluation ──────────────────────────────────────────────────────

## Coarse-simulates every proposal (threaded — [method BladeSim.simulate] is
## pure) and returns the top [constant _FINALIST_COUNT] by closest
## particle-to-enemy approach. Entries are
## [pivot, Array[SkillNode], bool swing_cw].
##
## Both directions of a selection compete for the same finalist slots rather
## than being decided here: this metric is a whole-sweep MINIMUM distance and
## knows nothing about spikes, so it ranks direction on path geometry alone.
## Whether a direction actually pays is settled downstream by
## [method _resolve_and_score]'s real pop gate. That is the split doing its
## job — the cheap tier orders, the expensive tier decides.
static func _coarse_rank_and_select(proposals: Array, entity: Entity, enemy_positions: Array[Vector2]) -> Array:
	var scored := []
	# Build every BladeState/driver set on the CALLING thread (touches
	# SkillNode positions/stats) before handing pure data to worker tasks.
	#
	# PASS A — geometry only. `build_blade_state` is handed an EMPTY defender
	# set, so it skips the field entirely; what we want from it here is the
	# blade's whip bound, which needs the built state (#811).
	var built := []
	var bounds: Dictionary = {}
	for proposal in proposals:
		var pivot: SkillNode = proposal[0]
		var blade_nodes: Array[SkillNode] = proposal[1]
		var probe := MeleeAttackPlan.new()
		probe.attacker = entity
		probe.source = pivot
		probe.blade_nodes = blade_nodes
		# Before build_drivers: `swing_cw` picks the arc drivers' sweep sign,
		# so setting it afterwards would rank a trajectory the finalist
		# resolve then never reproduces.
		probe.swing_cw = proposal[2]
		# #823 requirement 4: the coarse tier must see the same phantom clamps
		# the finalist resolve will — a rigidified handle swings measurably
		# differently (faster tip, different closest approach), so ranking an
		# unclamped geometry here would rank the wrong candidate.
		probe.ai_phantom_clamp_nodes = proposal[3]
		var state := probe.build_blade_state(BladeDefenderZones.new())
		if state == null:
			continue
		var drivers := probe.build_drivers(state)
		bounds[pivot] = maxf(
				float(bounds.get(pivot, 0.0)), MeleeAttackPlan.whip_bound(state))
		built.append([proposal, state, drivers, probe])
	# PASS B — ONE physics query per PIVOT, not one per proposal (#811). Up to
	# 192 proposals share at most 6 pivots, and a pivot's zone set is immutable
	# ([BladeDefenderZones]), so every proposal at that pivot can hold the same
	# instance while each gets its own mutable [BladeObstacleField] wrapper and
	# its own [BladeSwingClock]. Issuing it here also keeps the only
	# physics-server call on the CALLING thread, which is what lets the tasks
	# below consume the field as plain arrays.
	var zones_by_pivot: Dictionary = {}
	var task_ids: Array[int] = []
	for entry in built:
		var proposal: Array = entry[0]
		var pivot: SkillNode = proposal[0]
		var state: BladeState = entry[1]
		var drivers: Array[BladeDriver] = entry[2]
		var probe: MeleeAttackPlan = entry[3]
		if not zones_by_pivot.has(pivot):
			zones_by_pivot[pivot] = probe.query_defender_zones(
					pivot.global_position, float(bounds.get(pivot, 0.0)))
		MeleeAttackPlan.attach_defender_field(state, zones_by_pivot[pivot])
		# The coarse tier GAINS fortification drag here: before #811 it never
		# built a clock at all, so a wall that would bog the real swing down
		# ranked as if it were empty ground.
		var clock: BladeSwingClock = BladeSwingClock.new(MeleeAttackPlan.SWING_DURATION) \
				if state.obstacles != null else null
		var slot := [proposal, INF]
		scored.append(slot)
		var id := WorkerThreadPool.add_task(func() -> void:
			var traj := BladeSim.simulate(
					state, drivers, MeleeAttackPlan.SWING_DURATION, _COARSE_DT,
					_COARSE_ITERS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
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
		entity: Entity, pivot: SkillNode, blade_nodes: Array[SkillNode], swing_cw: bool,
		visible_enemies: Array[SkillNode], ai_tier: int,
		clamp_nodes: Array[SkillNode] = []) -> AiCombatScorer.ScoredCandidate:
	var plan := MeleeAttackPlan.new()
	plan.attacker = entity
	plan.source = pivot
	plan.blade_nodes = blade_nodes
	plan.swing_cw = swing_cw
	# #823 requirement 4: reach the FINALIST resolve too, not just the coarse
	# tier's own build_blade_state call — `resolve()` builds its own state
	# internally, so this has to be a field `build_blade_state` reads, never a
	# parameter that would stop at the coarse tier.
	plan.ai_phantom_clamp_nodes = clamp_nodes
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
			BattleSystem.AttackMode.MELEE, outcome, primary, entity, ai_tier, outcome.popped_nodes)
	candidate.source_node = pivot
	candidate.blade_nodes = blade_nodes
	candidate.swing_cw = swing_cw
	candidate.clamp_nodes = clamp_nodes
	return candidate


## The visible-hostile hit that LANDED the largest single damage instance — the
## candidate's kill/HP-comparison anchor for [AiCombatScorer]. A blade can hit
## several nodes at once; scoring still needs one representative target.
## Null if this swing didn't damage anyone currently visible (a coarse-ranked
## candidate that missed on full-fidelity resolve, or one every vertex of which
## popped).
##
## [b]Ranks on [member HitInstance.effective_amount], never `amount`[/b] (#692),
## for the same reason [method AiCombatScorer.expected_damage] sums it: `amount`
## is the PRE-gate number, and melee pre-filters nothing at resolve (#502). On a
## mixed swing — one arm popped on a spiked node, another landed on a plain one
## — an `amount` ranking names the node that took NOTHING, and
## [method AiCombatScorer.score] then measures the whole swing's EV against that
## node's HP: a blade that connected hard elsewhere collects
## [constant AiCombatScorer._KILL_BONUS] for a kill that cannot happen.
##
## The zero seed is deliberate, not inherited. It used to be -1.0, which with
## landed amounts would anchor a fully-popped swing on its first gated hit and
## emit a candidate that can only ever lose; at 0.0 with a strict compare, a
## swing that dealt nothing returns null and [method _resolve_and_score] drops
## it. A real hit that armour fully soaked is dropped on the same rule, which is
## the same call: it has no EV and cannot be a kill.
static func _primary_target(outcome: AttackOutcome, visible_enemies: Array[SkillNode]) -> SkillNode:
	var enemy_set: Dictionary = {}
	for e in visible_enemies:
		enemy_set[e] = true
	var best: SkillNode = null
	var best_amount := 0.0
	# damage_hits() is right HERE because this is SCORING — a rollout ranks
	# damage dealt. It is not a claim that melee only produces damage: a blade
	# into a node whose net `min_damage_taken` is negative flips to Kind.HEAL
	# exactly as a ranged shot does, and a RENDER pass must never filter it out
	# (see ArrowVolleyCoordinator). Here it is load-bearing: without it a swing
	# that healed the defender would rank itself as the biggest hit.
	for hit in outcome.damage_hits():
		if hit.target == null or not enemy_set.has(hit.target):
			continue
		if hit.effective_amount > best_amount:
			best_amount = hit.effective_amount
			best = hit.target
	return best
