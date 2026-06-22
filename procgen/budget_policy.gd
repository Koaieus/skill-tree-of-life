@tool
class_name BudgetPolicy
extends Resource

## Per-node modifier budget knobs, factored out of [NodeTypeDef]. v2 promotes
## budget to its own subresource so the same policy can serve many archetypes
## and so the spatial scalar field + per-role bonus compose cleanly with the
## archetype multiplier.
##
## Budget formula:
##   floor    = budget_floor_field.sample(position)   if set else base_min
##   ceiling  = budget_ceiling_field.sample(position) if set else base_max
##   raw      = lerp(floor, ceiling, rng.randf())
##   scaled   = raw
##            * archetype_multiplier.get(archetype, 1.0)
##            * budget_field.sample(position)         if set else 1.0
##            * Π role_bonus[t]                       for t in role_tags
##   budget   = max(1, round(scaled))
##
## The floor/ceiling split is the primary radial-shape lever: a typical setup
## has both as [RadialGradientField] but with different lo/hi pairs, so the
## outer ring's *floor* alone may already exceed the inner ring's *ceiling*
## (eliminating dead nodes). `budget_field` remains as an orthogonal global
## multiplier (e.g. difficulty), but is no longer the primary radial knob.
##
## Set [member modifier_pool] on the config and leave [member NodeTypeDef.budget_min]
## / `budget_max` in place — when [GraphProcgenConfig.budget_policy] is non-null
## it overrides the per-type values. Unset = falls back to per-type.

@export var base_min: int = 2
@export var base_max: int = 5

## Per-archetype scale on the rolled budget. Lookups default to 1.0 — list
## only the archetypes you want to depart from baseline.
@export var archetype_multiplier: Dictionary = {}

## Lower bound of the budget roll at this position. Typically a
## [RadialGradientField] with `inner_value = lo_floor`, `outer_value = hi_floor`.
## Unset = falls back to `base_min`.
@export var budget_floor_field: ScalarField

## Upper bound of the budget roll at this position. Typically a
## [RadialGradientField] with `inner_value = lo_ceiling`, `outer_value = hi_ceiling`.
## Unset = falls back to `base_max`.
@export var budget_ceiling_field: ScalarField

## Orthogonal global multiplier (e.g. difficulty). Composes on top of the
## floor/ceiling roll. Unset = neutral.
@export var budget_field: ScalarField

## Multiplicative per-role-tag bonuses. The procgen pass passes a list of role
## tags (e.g. [&"anomalous"] from [RandomBudgetBoost]); every matching key
## multiplies in. Missing keys are neutral (1.0).
@export var role_bonus: Dictionary = {}


func compute_budget(
		archetype: StringName,
		position: Vector2,
		role_tags: Array,
		rng: RandomNumberGenerator,
) -> int:
	var floor_v: float = float(base_min) if budget_floor_field == null else budget_floor_field.sample(position)
	var ceil_v: float = float(base_max) if budget_ceiling_field == null else budget_ceiling_field.sample(position)
	if ceil_v < floor_v:
		var tmp := floor_v
		floor_v = ceil_v
		ceil_v = tmp
	var raw := lerpf(floor_v, ceil_v, rng.randf())
	var arch_mult := float(archetype_multiplier.get(archetype, 1.0))
	var field_scale := 1.0 if budget_field == null else budget_field.sample(position)
	var role_mult := 1.0
	for t in role_tags:
		if role_bonus.has(t):
			role_mult *= float(role_bonus[t])
	var scaled := raw * arch_mult * field_scale * role_mult
	return maxi(1, int(round(scaled)))
