@tool
class_name GraphProcgen
extends RefCounted

## Pipeline runner. Static — no state beyond what flows through `generate`.
## Stages:
##   1. Poisson-disk sample positions inside the [ShapeMask] (with anchors).
##   2. Delaunay triangulate the points; that's our planar candidate edge set.
##   3. Prune to MST + a `connectivity`-controlled share of shortest extras
##      (stages 1–3 run as [ProcgenTopology]).
##   4. Cluster-assign an [ArchetypePolicy] per node (target-driven BFS-grow,
##      [ProcgenArchetypeStamper]).
##   4b. Placement pre-pass ([ProcgenPlacement]): guaranteed placements and
##       removable-blocker planning (indices, seeds, footprints, stakes, faces).
##   5. Per node ([ProcgenNodeRoll]), roll a budget ([BudgetPolicy]) and draw
##      modifiers from the node's archetype + universal [StatPool]s
##      (spend-until-broke v4 draw, [ProcgenModifierRoller]) after rolling its
##      subtype ([ProcgenSubtypeRoll]).
##   6. Instantiate SkillNodes ([ProcgenNodeRoll]) and wire the edges
##      ([ProcgenAssembler]) under the [Graph], with the post-loop addon pass
##      ([ProcgenAddonDraw]) between.
##
## Returns a Dictionary `{nodes: Array[SkillNode], starting_nodes:
## Array[SkillNode], starters: Array[StartingPoint], blockers:
## Array[Dictionary], config: GraphProcgenConfig}` — `config` is the copy
## generation resolved (the caller's is never written to); `starting_nodes[i]` is the SkillNode that landed on
## `config.starting.starting_points[i]`, for the caller to wire as entity cores, and
## each `blockers` entry is `{"node": SkillNode, "size": int, "prune_seed":
## int, "footprint": Array[SkillNode], "stake_level": int}` (`size` being a
## [EntityFactory.BlockerSize] int, `prune_seed` the loot-book prune's seed,
## `footprint` the bonus nodes the blocker also owns, `stake_level` the
## pre-stake in 1..3) for the caller to hand to `spawn_blocker`.

## Arbitrary offset mixed into the main `rng.seed` to derive [member
## ProcgenPlacement._place_blocker_indices]'s own RNG stream. Blocker placement
## has to run BEFORE the per-node content loop (so the loop can pick the right
## node scene), which would otherwise consume draws off the shared `rng` ahead
## of every other roll — silently reshuffling what a given seed generates
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
## Salt for the node-subtype placement roll, for the same reason as the
## two above and one more: the roll happens mid-loop, per node, so off the
## shared `rng` every modifier draw after it would shift — both goldens would
## churn on any `base_chance` retune and a placement change would be
## indistinguishable from a content change.
const _SUBTYPE_RNG_SALT := 0x5B17
## Salt for the addon placement pass's own stream (see [method ProcgenAddonDraw.run]).
const _ADDON_RNG_SALT := 0xADD0

## Poisson-disk auto-scale sizing: the disc area a ShapeMask needs to hold
## `node_count` points at spacing `min_dist`. ONE MEASURED constant (area per
## point Bridson achieves), set just above the measured curve so the flood exhausts
## at the `max_points` cap. Re-check `test_procgen_sizing.gd` before retuning.
## See docs/domain/procgen-sizing.md
const _POISSON_AREA_PER_POINT := 1.60

## Relative slack in [method node_count_for_area] so it stays an exact inverse
## of [method target_area_for_node_count] under float rounding. Far below any
## meaningful count difference; see that method.
const _ROUND_TRIP_EPSILON := 1e-9


## Area (in world units²) a ShapeMask needs so Poisson can comfortably place
## `node_count` points at `min_dist` spacing. Shape-agnostic — pair with a
## shape's own area→extent conversion (e.g. [method CircularShapeMask.size_for]).
static func target_area_for_node_count(node_count: int, min_dist: float) -> float:
	return float(maxi(1, node_count)) * min_dist * min_dist * _POISSON_AREA_PER_POINT


## Inverse of [method target_area_for_node_count]: how many points Poisson is
## expected to place in a region of `area` at `min_dist` spacing. Used by
## consumers that need to predict a count from a region size instead of the
## other way around (e.g. the "how many nodes does this stamp cover").
##
## `_ROUND_TRIP_EPSILON` exists because `floor` on a multiply-then-divide is
## not exact: `target_area_for_node_count(n)` fed straight back here can land
## a few ULPs under `n` and floor to `n - 1`. Whether it does depends on the
## bit pattern of `_POISSON_AREA_PER_POINT` — 1.60 happens to round-trip
## cleanly and the 1.799773 it replaced did not, which is luck, not a
## contract. Nudging up by a relative epsilon makes the inverse exact for
## every constant without changing any genuinely fractional prediction.
static func node_count_for_area(area: float, min_dist: float) -> int:
	if min_dist <= 0.0:
		return 0
	var exact := maxf(0.0, area) / (min_dist * min_dist * _POISSON_AREA_PER_POINT)
	return int(floor(exact * (1.0 + _ROUND_TRIP_EPSILON)))


## Convenience for circular regions (stamps): expected node count within a
## disc of `radius` at `min_dist` spacing.
static func node_count_for_radius(radius: float, min_dist: float) -> int:
	return node_count_for_area(PI * radius * radius, min_dist)


## When `progress_cb` is a valid Callable, `generate` becomes a coroutine —
## it emits progress in [0, 1] with a short label between stages and yields
## one `process_frame` per emit so the caller's UI can repaint. Pass an empty
## Callable (the default) for the synchronous fast path used by tests and
## headless tooling.
##
## Callers that pass `progress_cb` MUST `await` the call; the synchronous
## path returns the Dictionary directly.
static func generate(
		config: GraphProcgenConfig,
		graph: Graph,
		progress_cb: Callable = Callable(),
) -> Dictionary:
	assert(config != null, "GraphProcgen.generate: null config")
	assert(graph != null, "GraphProcgen.generate: null graph")
	assert(config.shape.shape_mask != null, "GraphProcgen.generate: config.shape.shape_mask is null")

	# The caller resolved the sentinel already — `GameSession.start` for a
	# real run, an explicit seed for a test or an editor preview. Generation is
	# not a resolution site: a seed nobody recorded is a run nobody can replay.
	# The resolve call behind the assert is the release-build floor (asserts are
	# debug-only) and is a no-op on any already-resolved seed.
	assert(config.seed != 0,
			"GraphProcgen.generate: unresolved seed sentinel — resolve it once up front "
			+ "via GameSession.start()/ensure_started() (or RunConfig.resolve_seed) (#457)")
	var rng := RandomNumberGenerator.new()
	rng.seed = RunConfig.resolve_seed(config.seed)

	# Generation resolves on its OWN copy and returns it as `"config"`; the
	# caller's config object is never written to (see resolve_config). Copy
	# before the first yield, so no frame ever runs on the caller's object.
	config = ProcgenTopology.resolve_config(config)
	await _emit_progress(progress_cb, 0.02, "Preparing shape")
	await _emit_progress(progress_cb, 0.05, "Sampling positions")
	# Stages 1–3 in one phase: starter assembly, Poisson sample, Delaunay +
	# prune. The two labels above and below bracket it — the phase never
	# touches the callback.
	var topo := ProcgenTopology.run(config, rng)
	var starters := topo.starters
	if not topo.ok:
		return {
				"nodes": [] as Array[SkillNode],
				"starting_nodes": [] as Array[SkillNode],
				"starters": starters,
				"config": config,
		}
	var positions := topo.positions
	await _emit_progress(progress_cb, 0.25, "Connecting edges")
	var edge_pairs := topo.edge_pairs
	await _emit_progress(progress_cb, 0.30, "Planning clusters")
	# Stage 4 plus the territory-stamp pass in one phase. The label above
	# brackets it — the phase never touches the callback.
	var type_assignments := ProcgenArchetypeStamper.run(
			positions, edge_pairs, config, rng)

	# Pre-roll placement pass: GuaranteedPlacements decorate nodes with role
	# tags, then removable-blocker placement is planned (on INDICES, before the
	# per-node loop — the edges and self-loops below wire `nodes` by reference,
	# so a node can't be replaced once added; the phase picks the scene from
	# the index map). Progress stays here; the phase never touches the
	# callback. Its body and draw order are unchanged, so a given seed still
	# generates the same map.
	await _emit_progress(progress_cb, 0.40, "Placing guarantees")
	var starter_indices := PackedInt32Array()
	for k in starters.size():
		starter_indices.append(k)
	# The phase's three salted streams are derived HERE, next to the subtype
	# and addon ones, so every salt stays visible on this file. Creating and
	# seeding an RNG consumes no draws — the phase's draw order is unchanged.
	var scene_rng := RandomNumberGenerator.new()
	scene_rng.seed = rng.seed + _SCENE_RNG_SALT
	var blocker_rng := RandomNumberGenerator.new()
	blocker_rng.seed = rng.seed + _BLOCKER_RNG_SALT
	var face_rng := RandomNumberGenerator.new()
	face_rng.seed = rng.seed + _FACE_RNG_SALT
	var placement := ProcgenPlacement.run(
			positions, edge_pairs, type_assignments, starter_indices, config, rng,
			scene_rng, blocker_rng, face_rng)
	var placement_ctx := placement.ctx
	var blocker_sizes := placement.blocker_sizes

	await _emit_progress(progress_cb, 0.45, "Rolling content")
	var nodes: Array[SkillNode] = []
	# INT-archetype nodes only — the spell-grant pool the roll fills.
	var int_nodes: Array[SkillNode] = []
	# Every non-authored-scene node: the addon pass's draw pool.
	var addon_eligible: Array[SkillNode] = []
	# Subtype placement — its own derived stream, plus the two things
	# that must be computed ONCE per generate(): the resolved default (D14) and
	# D13's per-(archetype, subtype) drawability lookup.
	var subtype_rng := RandomNumberGenerator.new()
	subtype_rng.seed = rng.seed + _SUBTYPE_RNG_SALT
	var default_subtype: NodeSubtype = null
	var subtype_drawable: Dictionary = {}
	if config.content != null:
		default_subtype = config.content.resolved_default_subtype()
		subtype_drawable = ProcgenSubtypeRoll.build_drawability(config.content)
	# Yield ~10 times across the per-node loop so the bar moves smoothly
	# without paying a frame per node. With 500 nodes that's every ~50.
	@warning_ignore("integer_division")
	var yield_every := maxi(1, positions.size() / 10)
	for i in positions.size():
		# One node per call: the loop (and its progress emits) stays here,
		# the roll body lives in the phase.
		ProcgenNodeRoll.run(
				i, positions, graph, placement_ctx, type_assignments, blocker_sizes,
				config, rng, subtype_rng, default_subtype, subtype_drawable,
				nodes, int_nodes, addon_eligible)
		if i > 0 and i % yield_every == 0:
			# 0.45 → 0.92 over the per-node loop.
			var frac: float = 0.45 + 0.47 * (float(i) / float(positions.size()))
			await _emit_progress(progress_cb, frac, "Rolling content")

	# Own derived stream (the blocker pass's precedent): retuning the addon
	# density never shifts the modifier rolls on the main `rng`.
	var addon_rng := RandomNumberGenerator.new()
	addon_rng.seed = rng.seed + _ADDON_RNG_SALT
	ProcgenAddonDraw.run(addon_eligible, nodes.size(), config, addon_rng)
	GraphProcgenSpellGrants.distribute(
			int_nodes, config.content.spell_grant_pool, config.content.spell_grant_ratio, rng)

	await _emit_progress(progress_cb, 0.95, "Wiring edges")
	var assembled := ProcgenAssembler.run(
			graph, nodes, edge_pairs, starters.size(), config, rng,
			blocker_sizes, placement.blocker_seeds, placement.blocker_footprints,
			placement.blocker_stakes, placement.blocker_faces)

	await _emit_progress(progress_cb, 1.0, "Done")
	return {
		"nodes": nodes,
		"starting_nodes": assembled.starting_nodes,
		"starters": starters,
		"blockers": assembled.blockers,
		"config": config,
	}


## Calls `progress_cb` (if valid) and yields one process_frame so the caller's
## UI can repaint. No-op + no yield when callback is empty — keeps synchronous
## callers truly synchronous.
static func _emit_progress(progress_cb: Callable, frac: float, label: String) -> void:
	if not progress_cb.is_valid():
		return
	progress_cb.call(frac, label)
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		await (tree as SceneTree).process_frame
