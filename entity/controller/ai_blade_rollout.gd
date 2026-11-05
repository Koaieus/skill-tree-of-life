class_name AiBladeRollout
extends RefCounted

## Melee candidate rollout: bounds the search instead of enumerating it. (1) free
## reach-bound rejection of pivots, (2) a few steerable proposals per pivot,
## (3) coarse off-thread sim ranking, full resolve (hit scan) of finalists on the
## main thread only. `popped_nodes` fed to the scorer is `AttackOutcome.popped_nodes`.
## See docs/domain/ai-blade-rollout.md

## The clamp's scene; its `resource_path` is the clamp's addon kind
## ([method SkillNodeAddon.get_kind]).
const _CLAMP_SCENE: PackedScene = preload("res://skill_node/addons/defs/clamp_addon.tscn")
## Pivots kept after the free reach-bound rejection, nearest-to-an-enemy
## first — bounds proposal generation regardless of territory size.
const _MAX_PIVOTS := 6
## 64, not 16 — 50+-member blades are mid-game, not endgame: a 16 cap would
## have the AI swing roughly a third of its weapon at mid-game budgets and spend
## nothing on the upgrade half. Still a
## guard, not a real ceiling — a pathological board making the chain-growth
## loop unbounded — and only affordable because the generator is bounded
## (≤4 proposals/pivot) independent of `blade_size`. NOT tier-gated: this is
## a bug fix and applies at `ai_tier = 0` too.
const _MAX_BLADE_SIZE_SAFETY := 64
## Finalists promoted to full-fidelity resolve + hit scan.
const _FINALIST_COUNT := 3
const _COARSE_DT := 1.0 / 30.0
const _COARSE_ITERS := 4


## Every melee candidate worth scoring this turn, already scored via
## [AiCombatScorer]. Empty if the entity has no owned territory, no visible
## enemy, or every pivot fails the reach-bound rejection.
static func gather_melee_candidates(
		entity: Entity, visible_enemies: Array[SkillNode], ai_tier: int,
		rng: RandomNumberGenerator = null,
		loot_system: LootSystem = null) -> Array[AiCombatScorer.ScoredCandidate]:
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

	# Hop distance from the entity's own core, for the reach phase's
	# "prefer spiked nodes far from core" preference — computed once per
	# entity, not per candidate. Empty (never rejects a candidate; distance
	# just reads 0 for everyone, so only the spike preference survives) when
	# the entity has no core yet, which core-move / early-setup fixtures hit.
	var core_distances: Dictionary[SkillNode, int] = {}
	if entity.core_location != null:
		core_distances = entity.navigator.hop_distances_from(entity.core_location)

	var proposals := _propose_blade_selections(
			pivot_infos, adjacency, target_centroid, ai_tier, rng, core_distances)
	if proposals.is_empty():
		return out

	var finalists := _coarse_rank_and_select(proposals, entity, enemy_positions)
	for f in finalists:
		var pivot: SkillNode = f[0]
		var blade_nodes: Array[SkillNode] = f[1]
		var clamp_nodes: Array[SkillNode] = f[3]
		var candidate := _resolve_and_score(
				entity, pivot, blade_nodes, f[2], visible_enemies, ai_tier, clamp_nodes,
				loot_system)
		if candidate != null:
			out.append(candidate)
	return out


# ── Territory + free rejection ──────────────────────────────────────────────

## Owned SkillNode -> Array[SkillNode] of its neighbours that are ALSO owned
## by [param entity] — the walkable graph for blade pivot/member selection.
## The territory mirror already IS that filter: [EntityNavigator] only holds
## edges between owned nodes, so [method GraphMirror.neighbours_of] is the
## owned neighbourhood with no `owned_by` re-check. Sorted by
## stable_id inside the mirror, so the rollout's walk is peer-reproducible.
static func _owned_adjacency(entity: Entity) -> Dictionary:
	var out: Dictionary = {}
	if entity.navigator == null or entity.navigator.graph == null:
		return out
	var nav := entity.navigator
	for n in nav.get_mirrored_nodes():
		out[n] = nav.neighbours_of(n)
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
## and the swing-direction fixture) keeps compiling and reproducible
## without threading a seed through every call site.
static func _default_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return r


## Per surviving [pivot, max_size]: one consecutive handle plus a reach extension,
## a handful of proposals (at most 4) per pivot in BOTH swing directions.
## Direction is part of a candidate's identity: both enter the same ranking and
## the same finalist resolve.
## See docs/domain/ai-blade-rollout.md
static func _propose_blade_selections(
		pivot_infos: Array, adjacency: Dictionary, target_centroid: Vector2,
		ai_tier: int = 1, rng: RandomNumberGenerator = null,
		core_distances: Dictionary = {}) -> Array:
	var actual_rng := rng if rng != null else _default_rng()
	var out := []
	for info in pivot_infos:
		var pivot: SkillNode = info[0]
		var max_size: int = info[1]
		if max_size <= 0:
			continue
		# D4: target handle length = randi_range(tier, tier + 1), tier clamped
		# to the AIController.Tier ladder (BRAWLER -> 0-1 ... WARLORD -> 3-4). All rigidity-seeking lives in this
		# tier ladder and nowhere else (hub, owner 2026-09-10: "0-1
		# means sometimes no clamping attempt at all, just flop. or
		# accidental truss, all good. t0 AI accidentally making a functional
		# blade is cool, they just dont pursue it as effectively.").
		var tier := clampi(ai_tier, AIController.Tier.BRAWLER, AIController.Tier.WARLORD)
		var handle_target := actual_rng.randi_range(tier, tier + 1)
		var archetype := _build_archetype(
				pivot, adjacency, target_centroid, max_size, handle_target, core_distances)
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


## The two-step archetype (D1) for one pivot: rigidify a handle
## consecutive from the pivot outward, THEN spend whatever budget remains on a
## reach extension that prefers spiked, far-from-core nodes. Single
## pass, budget-correct by construction — `spent` never exceeds `max_size`,
## the ONE budget shared between members and clamps
## (`.claude/rules/blade-budget-and-clamps.md`); the n-th clamp pays the
## clamp's escalating temp price. Returns {members: Array[SkillNode], clamps:
## Array[SkillNode] (subset of members), spent: int (the plan's blade_size spend)}.
##
## [b]HANDLE member selection is unconditionally geometric — [method
## _grow_path] decides `path` before this function ever runs.[/b] Requirement
## 3 is a BUDGET rule, not a selection bias: free rigidity (an
## already-triangulated joint, or one already carrying a procgen
## [ClampAddon]) is taken when the walk happens to pass through it, never
## hunted for. A tier-0 blade that comes out rigid over already-triangulated
## territory does so by accident, exactly as the owner specified.
##
## REACH member selection is a SEPARATE walk from the handle's tip
## (see [method _reach_score]/[method _extend_reach] below) — it does NOT
## consume the rest of `path`. `path` is grown toward the enemy centroid,
## which is what makes it right for the handle (D2's rigidity mechanic is
## about consecutive-from-pivot joints, not about where the enemy is); reach
## has already cleared the free reach-bound rejection by the time this runs,
## so what's left to optimize is the reach preference, not centroid
## direction. This is also why the triangle look-ahead (reading
## `[pivot] + path` rather than just the paid members) is unaffected:
## the triangulation check below only ever queries `edges` for handle-range
## `path` indices, and reach members never reach that check at all.
static func _build_archetype(
		pivot: SkillNode, adjacency: Dictionary, target_centroid: Vector2,
		max_size: int, handle_target: int, core_distances: Dictionary = {}) -> Dictionary:
	var path := _grow_path(pivot, adjacency, target_centroid, max_size)
	# Triangulation is checked against the FULL candidate path up front, not
	# incrementally as `members` grows — the HANDLE phase below (only) ends up
	# an exact PREFIX of `path` (it only ever consumes `path` in order, never
	# skips), so a path node's real graph neighbours are the right set to ask
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
		elif spent + _next_clamp_cost(clamps.size()) <= max_size \
				and node.can_attach_addon(_CLAMP_SCENE.resource_path):
			spent += _next_clamp_cost(clamps.size())
			clamps.append(node)
			rigidified += 1
		else:
			# A gap here (no budget, or the slot's already full) means
			# nothing further out ever compounds — stop rigidifying. `node`
			# stays a plain member; it was already paid for above.
			handle_open = false
		i += 1
	# Reach extension — its OWN outward walk from the handle's tip
	# (pivot, if the handle is empty), scored by _reach_score rather than
	# continuing along `path`. See this function's doc comment for why that's
	# safe w.r.t. the triangle look-ahead.
	if spent < max_size:
		var selected: Dictionary = {pivot: true}
		for m in members:
			selected[m] = true
		var tip: SkillNode = members[-1] if not members.is_empty() else pivot
		var reach := _extend_reach(tip, adjacency, selected, core_distances, max_size - spent)
		members.append_array(reach)
		spent += reach.size()
	return {members = members, clamps = clamps, spent = spent}


## What the swing's next temp clamp costs once it carries [param already] —
## the addon's own escalating price, so the AI and the plan never disagree.
static func _next_clamp_cost(already: int) -> int:
	return SkillNodeAddon.temp_costs_of(_CLAMP_SCENE, already).get(&"blade_size", 1)


## A single consecutive walk outward from [param pivot] toward [param
## target_pos] (closest-unselected-neighbour-of-the-TIP-first) — a genuine
## PATH, unlike the retired `_greedy_chain` which grew from the whole selected
## set and so could branch into a star/tree. The "handle" mechanic
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


## Dwarfs [method _reach_score]'s distance term so a spiked node
## always outranks a plain one regardless of how far the plain one is; the
## owner's phrasing ("mostly preferring spiked nodes ... far from core") is
## spike-first, distance as the tiebreak/amplifier among spikes.
const _SPIKE_REACH_BONUS := 1000.0


## The reach-phase preference: how attractive [param node] is as the next
## pick, once the handle is settled and centroid direction has already done
## its job (this pivot cleared [method _reach_bound]; the actual swing
## direction and contact are judged downstream by the coarse rank + finalist
## resolve, never estimated here — see the class doc's point 3). Spiked
## nodes dominate — [SpikeRingAddon]'s own `blade_damage` modifiers
## (+3, x1.5 — node-local, NOT scaled by allocation level; what scales with
## `stake_level` is `addon_slots` and the defensive pop budget, per the 
## hub correction) — tie-broken/amplified by hop distance from [param
## entity]'s core ([param distances], the `GraphMirror.hop_distances_from`
## helper — 0 for anything it didn't reach, which never outranks a real
## candidate since every candidate here is drawn from owned-territory
## `adjacency` already).
static func _reach_score(node: SkillNode, distances: Dictionary) -> float:
	var score: float = float(distances.get(node, 0))
	if node.has_addon(SpikeRingAddon):
		score += _SPIKE_REACH_BONUS
	return score


## The reach-phase walk: from [param tip], greedily pick the
## highest-[method _reach_score] unselected neighbour, move the tip there,
## repeat up to [param budget] times or until the tip runs out of unselected
## neighbours (a dead end reads as a "flail" tip — the walk simply stops
## there rather than backtracking to find more). A single consecutive walk,
## like [method _grow_path], but steered by the preference instead of
## centroid direction: at a fork, a neighbour carrying a spike ("pocket
## picking" a nearby prize) can outrank one that's merely further along —
## the minor variation the owner rates as not worth a named archetype (D1),
## folded into ONE score rather than a second proposal (the ≤4/pivot bound
## stays a property of [method _propose_blade_selections]'s variant count,
## untouched here). [param selected] is mutated: entries this walk adds stay
## marked so a caller building on top of it never re-picks them.
static func _extend_reach(tip: SkillNode, adjacency: Dictionary, selected: Dictionary,
		distances: Dictionary, budget: int) -> Array[SkillNode]:
	var added: Array[SkillNode] = []
	var cur := tip
	for _i in budget:
		var best: SkillNode = null
		var best_score := -INF
		for nb in adjacency.get(cur, []):
			if selected.has(nb):
				continue
			var s := _reach_score(nb, distances)
			if s > best_score:
				best_score = s
				best = nb
		if best == null:
			break
		added.append(best)
		selected[best] = true
		cur = best
	return added


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
	# blade's whip bound, which needs the built state.
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
		# The coarse tier must see the same phantom clamps
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
	# PASS B — ONE physics query per PIVOT, not one per proposal. Up to
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
		# The coarse tier models swing drag here: without a clock, a wall that
		# would bog the real swing down would rank as if it were empty ground.
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
	var order := top_k_indices(scored, func(a, b): return a[1] < b[1], _FINALIST_COUNT)
	var out := []
	for i in order:
		out.append(scored[i][0])
	return out


## Generic top-K promotion. Ranks [param items] by [param is_better]
## (the [method Array.sort_custom] contract: true iff its first argument
## should sort ahead of its second) and returns the best [param k] as INDICES
## into [param items], in RANK order (best first) — never re-sorted into
## [param items]'s own order, since the caller's enumeration order can itself
## be load-bearing (a fog list, a spell/source loop) and this helper has no
## opinion on it.
##
## The single top-K selection contract shared by melee's own coarse → finalist
## split above and [AIController]'s ranged/magic two-tier gates — factored out
## rather than reimplemented per mode (`.claude/rules/` forbids two accessor
## impls of one contract). A caller that needs the promoted subset back in its
## OWN order (ranged/magic, whose downstream tie-break and fog-order
## characterization tests pin the ORIGINAL enumeration order, not score order)
## sorts this return value again — see [method AIController._gather_ranged_candidates].
static func top_k_indices(items: Array, is_better: Callable, k: int) -> Array[int]:
	var order: Array[int] = []
	for i in items.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return is_better.call(items[a], items[b]))
	if order.size() > k:
		order = order.slice(0, k)
	return order


## [param traj] may be NULL — [method BladeSim.simulate] answers null (after its
## own `push_error` naming the cause) when the native solver is missing, stale,
## or declines the inputs, and there is no GDScript fallback to catch
## that. This runs inside a [WorkerThreadPool] task, so dereferencing it would
## bury that diagnosis under a nil-access crash on a worker thread. A swing that
## could not be simulated scores INF — ranked last, never chosen.
static func _closest_approach(traj: BladeTrajectory, enemy_positions: Array[Vector2]) -> float:
	var best := INF
	if traj == null:
		return best
	for sample in traj.samples:
		for i in sample.size():
			for ep in enemy_positions:
				best = minf(best, sample[i].distance_to(ep))
	return best


# ── Full-fidelity resolve + scoring (main thread only) ──────────────────────

static func _resolve_and_score(
		entity: Entity, pivot: SkillNode, blade_nodes: Array[SkillNode], swing_cw: bool,
		visible_enemies: Array[SkillNode], ai_tier: int,
		clamp_nodes: Array[SkillNode] = [],
		loot_system: LootSystem = null) -> AiCombatScorer.ScoredCandidate:
	var plan := MeleeAttackPlan.new()
	plan.attacker = entity
	plan.source = pivot
	plan.blade_nodes = blade_nodes
	plan.swing_cw = swing_cw
	# Reach the FINALIST resolve too, not just the coarse
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
			BattleSystem.AttackMode.MELEE, outcome, primary, entity, ai_tier, outcome.popped_nodes,
			loot_system)
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
## [b]Ranks on [member HitInstance.effective_amount], never `amount`[/b],
## for the same reason [method AiCombatScorer.expected_damage] sums it: `amount`
## is the PRE-gate number, and melee pre-filters nothing at resolve. On a
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
