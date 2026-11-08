@tool
class_name ProcgenPlacement
extends RefCounted

## Placement phase of [method GraphProcgen.generate] (hub #422, child 4),
## extracted from `graph_procgen.gd` with its body unchanged: the
## GuaranteedPlacement pre-pass (PlacementContext + role tags + scene slots),
## removable-blocker planning (indices, prune seeds, footprints, pre-stakes,
## faces) and the per-node radius stamp helper. Static and stateless — the
## caller owns the main RNG and hands it in; blocker and face draws ride their
## own salted streams so the main stream is untouched, and this phase never
## touches the progress callback. Same seed → byte-identical graph is guarded
## by `test/integration/procgen/test_procgen_golden.gd`.
## See docs/domain/procgen-v4.md and docs/domain/procgen.md.

## Arbitrary offset mixed into the main `rng.seed` to derive [member
## _place_blocker_indices]'s own RNG stream. Blocker placement has to
## run BEFORE the per-node content loop (so the loop can pick the right node
## scene), which would otherwise consume draws off the shared `rng` ahead of
## every other roll — silently reshuffling what a given seed generates
## everywhere else. A same-seed-derived-but-independent stream keeps blocker
## placement itself deterministic while leaving the main stream untouched.
const _BLOCKER_RNG_SALT := 0x8477
## Salt for [member PlacementContext.scene_rng] — scene placements draw
## off their own derived stream so the main `rng` is byte-identical with or
## without them.
const _SCENE_RNG_SALT := 0x3300
## Salt for the Dormant Core face roll ([method GraphProcgenBlockers.roll_faces]):
## its own stream, so faces on or off leave every blocker draw above it intact.
const _FACE_RNG_SALT := 0xFACE


## What [method run] hands back: the placement context the per-node loop reads
## (scene slots / role tags) plus everything the blocker pass planned, in draw
## order.
class Result extends RefCounted:
	var ctx: PlacementContext = null
	var blocker_sizes: Dictionary = {}
	var blocker_seeds: Dictionary[int, int] = {}
	var blocker_footprints: Dictionary = {}
	var blocker_stakes: Dictionary[int, int] = {}
	var blocker_faces: Dictionary = {}


## Builds the placement context, applies every GuaranteedPlacement in authored
## order, then plans the removable blockers. Progress stays in `generate` — this
## phase never touches the callback.
static func run(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		type_assignments: PackedInt32Array,
		starter_indices: PackedInt32Array,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> Result:
	var out := Result.new()
	# Pre-roll pass: GuaranteedPlacements decorate nodes with role tags.
	# starting_points were placed first into the position list (by index).
	var placement_ctx := _build_placement_context(
			positions, edge_pairs, type_assignments, starter_indices, config, rng)
	out.ctx = placement_ctx
	for placement in config.content.guaranteed_placements:
		if placement != null:
			placement.apply(placement_ctx)

	# Removable-blocker placement. Computed on INDICES before the
	# per-node loop so a blocked node can be instantiated from
	# [constant GraphProcgen._BLOCKER_NODE_SCENE] (the boulder visual) rather than
	# swapped in afterwards — the edges and self-loops in `generate` wire `nodes`
	# by reference, so a node can't be replaced once added. Eligibility mirrors
	# the old post-loop pass: never a starter core (indices < starters.size())
	# nor an authored-scene node (placement_ctx.scenes[i] != null) —
	# plus, never a node inside the core safe radius
	# (blocker_min_hops_from_core).
	#
	# Deliberately rides its OWN derived RNG, not the shared `rng` stream:
	# running this before the per-node content loop (needed so the loop can
	# pick the right scene) would otherwise shift every subsequent draw off
	# `rng` — silently changing what a given seed generates for the rest of
	# `generate` (archetype rolls, modifier rolls, self-loops, ...). Deriving
	# from `config.seed` keeps the main stream byte-for-byte identical to
	# before blockers existed.
	var blocker_rng := RandomNumberGenerator.new()
	blocker_rng.seed = rng.seed + _BLOCKER_RNG_SALT
	var blocker_sizes := _place_blocker_indices(
			positions.size(), placement_ctx, config, blocker_rng)
	out.blocker_sizes = blocker_sizes
	# One prune seed per placement, drawn HERE rather than at spawn
	# time because the level scene is re-run on every peer — the loot-book
	# prune is reproduced, not received, so an unseeded roll there would hand
	# two peers different offers off the same relic (multiplayer-sync.md).
	# Same dedicated stream as the placement above, so the main `rng` is
	# untouched and a given seed still generates the same map.
	var blocker_seeds: Dictionary[int, int] = {}
	for idx: int in blocker_sizes:
		blocker_seeds[idx] = blocker_rng.randi()
	out.blocker_seeds = blocker_seeds
	# Bonus-node footprints, drawn LAST off the same stream so every
	# draw above — the cores, the sizes, the prune seeds — is byte-for-byte
	# what an earlier seed produced. Appending is the whole reason this is a
	# separate pass rather than a branch inside the placement loop.
	out.blocker_footprints = _place_blocker_footprints(
			blocker_sizes, placement_ctx, config, blocker_rng)
	# Pre-stake rolls, drawn after the footprints off the same stream
	# and for the same reason: appended last, so every draw above is what an
	# earlier seed produced. Always two draws per blocker, chance or not, so
	# a later pass appended here is stable across a chance retune too.
	out.blocker_stakes = _roll_blocker_stakes(blocker_sizes, config.blockers, blocker_rng)
	var face_rng := RandomNumberGenerator.new()
	face_rng.seed = rng.seed + _FACE_RNG_SALT
	out.blocker_faces = config.blockers.roll_faces(blocker_sizes.keys(), face_rng)
	return out


# ── GuaranteedPlacement pre-pass ─────────────────────────────────────────


static func _build_placement_context(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		type_assignments: PackedInt32Array,
		starter_indices: PackedInt32Array,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> PlacementContext:
	var ctx := PlacementContext.new()
	ctx.positions = positions
	ctx.edge_pairs = edge_pairs
	ctx.type_assignments = type_assignments
	ctx.starter_indices = starter_indices
	ctx.config = config
	ctx.rng = rng
	# Adjacency.
	var adj: Array[PackedInt32Array] = []
	for i in positions.size():
		adj.append(PackedInt32Array())
	for e in edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	ctx.adjacency = adj
	# Per-node empty role-tag arrays + null scene slots.
	var rt: Array = []
	rt.resize(positions.size())
	for i in positions.size():
		rt[i] = [] as Array[StringName]
	ctx.role_tags = rt
	var sc: Array = []
	sc.resize(positions.size())
	ctx.scenes = sc
	# Derived stream, same reason as the blocker pass below: scene
	# draws never shift the main `rng`, and every peer reproduces the picks.
	ctx.scene_rng = RandomNumberGenerator.new()
	ctx.scene_rng.seed = rng.seed + _SCENE_RNG_SALT
	return ctx


# ── Removable-blocker placement ───────────────────────────────────


## Pre-loop pass picking which node INDICES get a removable blocker, per size
## tier (`floor(node_count / denom)`, sampled without replacement). Excludes
## starter cores, authored-scene nodes and the safe hop-ball around any starter.
## The basis is the AUTHORED `node_count`. Uses its own derived rng.
## See docs/domain/procgen-v4.md
static func _place_blocker_indices(
		positions_count: int,
		ctx: PlacementContext,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> Dictionary:
	var out: Dictionary = {}
	var scenes: Array = ctx.scenes
	var starter_count := ctx.starter_indices.size()
	# Core safe radius: union of the hop-balls around every starter.
	var too_close := {}
	if config.blockers.blocker_min_hops_from_core > 0:
		for s in ctx.starter_indices:
			for n in ctx.nodes_within_hops(s, config.blockers.blocker_min_hops_from_core):
				too_close[n] = true
	var eligible: Array[int] = []
	for i in positions_count:
		if i < starter_count:
			continue
		if i < scenes.size() and scenes[i] != null:
			continue
		if too_close.has(i):
			continue
		eligible.append(i)
	if eligible.is_empty():
		if not too_close.is_empty():
			push_warning("GraphProcgen: no blocker-eligible node outside the %d-hop core safe radius — placing none" % config.blockers.blocker_min_hops_from_core)
		return out

	# Small → medium → large (most numerous first). Each tier partial-Fisher-
	# Yates-shuffles the front of the remaining pool and slices the winners off,
	# so no node can be picked by two tiers.
	var tiers: Array = [
		[config.blockers.blocker_per_small, EntityFactory.BlockerSize.SMALL],
		[config.blockers.blocker_per_medium, EntityFactory.BlockerSize.MEDIUM],
		[config.blockers.blocker_per_large, EntityFactory.BlockerSize.LARGE],
	]
	for tier in tiers:
		var denom: int = tier[0]
		if denom <= 0:
			continue
		# Clamp positive-but-too-small denominators up to the safety floor
		# Denom 1..4 would otherwise place a blocker on nearly every
		# node, so a joker authoring `1` still gets `5`.
		denom = maxi(denom, GraphProcgenBlockers.MIN_BLOCKER_PER)
		# node_count, not positions_count/eligible.size() — see docstring.
		var count := int(floor(float(config.topology.node_count) / float(denom)))
		count = mini(count, eligible.size())
		for i in count:
			var j := i + rng.randi() % (eligible.size() - i)
			var tmp: int = eligible[i]
			eligible[i] = eligible[j]
			eligible[j] = tmp
			out[eligible[i]] = int(tier[1])
		eligible = eligible.slice(count)
	return out



## The pre-stake per placed blocker: a chain of two draws against the
## tier's chance — P(stake 2), then P(stake 3 | stake 2) — so with chance `p`
## the split is `1−p : p(1−p) : p²`. Draws are ALWAYS consumed (both of them,
## whatever the chance) so the stream stays aligned across a retune. 1..3 by
## construction; a stake past the core's ceiling raises the ceiling
## ([method EntityFactory.set_procgen_stake]).
static func _roll_blocker_stakes(
	blocker_sizes: Dictionary, blockers: GraphProcgenBlockers,
	blocker_rng: RandomNumberGenerator
) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for idx: int in blocker_sizes:
		var chance := blockers.stake_chance(int(blocker_sizes[idx])) if blockers != null else 0.0
		var stake := 1
		var first := blocker_rng.randf()
		var second := blocker_rng.randf()
		if chance > 0.0 and first < chance:
			stake = 2
			if second < chance:
				stake = 3
		out[idx] = stake
	return out


## Grow each placed blocker's bonus-node FOOTPRINT: randomized frontier growth
## (connected by construction) over eligible nodes, in tier order. Returns index ->
## PackedInt32Array of bonus-node indices (core excluded); short of candidates a
## blocker shrinks rather than steals a claim.
## See docs/domain/procgen-v4.md
static func _place_blocker_footprints(
		blocker_sizes: Dictionary,
		ctx: PlacementContext,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> Dictionary:
	var out: Dictionary = {}
	if blocker_sizes.is_empty():
		return out
	var mods := config.blockers
	# Nothing authored anywhere → skip the walk (and every draw it would make),
	# so a preset that opts out generates exactly what a pre-footprint seed did.
	var wants_footprints := false
	for size: int in [0, 1, 2]:
		if mods.footprint_range(size).y > 0:
			wants_footprints = true
			break
	if not wants_footprints:
		return out

	var scenes: Array = ctx.scenes
	var starter_count := ctx.starter_indices.size()
	var too_close := {}
	if mods.blocker_min_hops_from_core > 0:
		for st in ctx.starter_indices:
			for n in ctx.nodes_within_hops(st, mods.blocker_min_hops_from_core):
				too_close[n] = true
	# Every blocker core is claimed up front — a core placed later in the tier
	# order must not be swallowed by an earlier blocker's footprint.
	var claimed: Dictionary[int, bool] = {}
	for idx: int in blocker_sizes:
		claimed[idx] = true

	for idx: int in blocker_sizes:
		var span := mods.footprint_range(int(blocker_sizes[idx]))
		var want := rng.randi_range(span.x, span.y)
		if want <= 0:
			continue
		var grown := PackedInt32Array()
		# The live frontier: eligible, unclaimed nodes adjacent to the blocker's
		# current territory. Rebuilt incrementally as the walk grows.
		var frontier: Array[int] = []
		var in_frontier: Dictionary[int, bool] = {}
		var push_neighbours := func(n: int) -> void:
			for nb: int in ctx.adjacency[n]:
				if claimed.has(nb) or in_frontier.has(nb):
					continue
				if nb < starter_count:
					continue
				if nb < scenes.size() and scenes[nb] != null:
					continue
				if too_close.has(nb):
					continue
				in_frontier[nb] = true
				frontier.append(nb)
		push_neighbours.call(idx)
		while grown.size() < want and not frontier.is_empty():
			var pick := rng.randi() % frontier.size()
			var node_idx: int = frontier[pick]
			# Swap-remove: order in `frontier` is not meaningful, and the draw
			# above already randomized the choice.
			frontier[pick] = frontier[frontier.size() - 1]
			frontier.resize(frontier.size() - 1)
			in_frontier.erase(node_idx)
			claimed[node_idx] = true
			grown.append(node_idx)
			push_neighbours.call(node_idx)
		if not grown.is_empty():
			out[idx] = grown
	return out


# ── Per-node radius stamp ──────────────────────────────────────────────


## Procgen writes only the authored `base_*` pair (`radius` / `inner_radius`
## are derived, stake growth on top — see SkillNode). The inner disk keeps a
## constant 8px ring, today's 32/24, so the fill scales with the node.
const _INNER_RING_PX := 8.0


static func _stamp_radius(sn: SkillNode, base_radius: float) -> void:
	sn.base_radius = base_radius
	sn.base_inner_radius = base_radius - _INNER_RING_PX
