@tool
class_name ScenePlacement
extends GuaranteedPlacement

## Places [member min_count]..[member max_count] copies of a hand-authored
## [SkillNode] scene (a keystone — an inherited scene of
## `entity/keystone/keystone_skill_node.tscn`) on generated positions, drawn
## without replacement and weighted by [member weight]. The placement writes
## the scene into [member PlacementContext.scenes]; the per-node loop then
## instantiates THAT scene as node `i` instead of the plain skill node, and
## the scene is the whole content — no archetype, no modifier roll, no rolled
## addons, no radius ramp (#336: "a landmark outranks its terrain").
##
## The scene knows nothing about how often it appears: multiplicity and
## spatial bias are the preset's call, authored here, so one scene can be
## common in one preset and rare in another.
##
## Draws come off [member PlacementContext.scene_rng], a stream derived from
## the run seed (same reason as the blocker pass in [GraphProcgen]): the main
## stream is untouched, so a preset with and without keystones rolls the same
## terrain.

## The authored node scene. Null = this placement is a no-op.
@export var node_scene: PackedScene
## Inclusive uniform range of copies to place. Unique landmark: 1/1; "maybe
## one": 0/1; a handful: 2/4; scattered-but-never-absent: 1/N.
@export var min_count: int = 1
@export var max_count: int = 1
## Spatial bias, sampled at each candidate position; null = uniform. Reuses
## the budget-field family ([RadialGradientField], [GaussianBumpField], ...).
## A candidate whose sample is <= 0 is never picked.
@export var weight: ScalarField = null
## Never place on a starter core.
@export var exclude_starters: bool = true
## Candidates within this many hops (inclusive) of any starter are skipped
## (0 = off).
@export var min_hops_from_starter: int = 0
## Optional role tag stamped alongside the scene — debug overlays and
## [BudgetPolicy.role_bonus] hooks.
@export var role_tag: StringName = &"keystone"


func apply(context: PlacementContext) -> void:
	if context == null or node_scene == null or context.scene_rng == null:
		return
	var n := context.positions.size()
	if n == 0 or context.scenes.size() < n:
		return
	var count := context.scene_rng.randi_range(mini(min_count, max_count), maxi(min_count, max_count))
	if count <= 0:
		return
	# Eligibility: not a starter, not inside any starter's hop-ball, not a
	# slot another placement already filled (first entry wins), not a
	# candidate the weight field rejects.
	var excluded := {}
	if exclude_starters:
		for s in context.starter_indices:
			excluded[s] = true
	if min_hops_from_starter > 0:
		for s in context.starter_indices:
			for m in context.nodes_within_hops(s, min_hops_from_starter):
				excluded[m] = true
	var candidates: Array[int] = []
	var weights: Array[float] = []
	for i in n:
		if excluded.has(i) or context.scenes[i] != null:
			continue
		var w := 1.0
		if weight != null:
			w = weight.sample(context.positions[i])
		if w <= 0.0:
			continue
		candidates.append(i)
		weights.append(w)
	var take := mini(count, candidates.size())
	if take < count:
		push_warning("ScenePlacement: only %d of %d eligible slots for %s" % [take, count, node_scene.resource_path])
	# Weighted draw without replacement: pick by cumulative weight, then swap
	# the pick out of the live prefix.
	for k in take:
		var total := 0.0
		for j in range(k, candidates.size()):
			total += weights[j]
		var r := context.scene_rng.randf() * total
		var pick := candidates.size() - 1
		var acc := 0.0
		for j in range(k, candidates.size()):
			acc += weights[j]
			if r < acc:
				pick = j
				break
		var ci := candidates[pick]
		candidates[pick] = candidates[k]
		candidates[k] = ci
		var wi := weights[pick]
		weights[pick] = weights[k]
		weights[k] = wi
		context.scenes[ci] = node_scene
		if role_tag != &"":
			context.add_role_tag(ci, role_tag)
