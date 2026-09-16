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
## Candidates within this many hops of any starter are skipped (0 = off).
@export var min_hops_from_starter: int = 0
## Optional role tag stamped alongside the scene — debug overlays and
## [BudgetPolicy.role_bonus] hooks.
@export var role_tag: StringName = &"keystone"


func apply(_context: PlacementContext) -> void:
	# TODO(#330): draw count off scene_rng, weighted draw without replacement
	# over eligible indices (not a starter, not already holding a scene, not
	# inside the starter hop-ball), write context.scenes[i] + role tag.
	pass
