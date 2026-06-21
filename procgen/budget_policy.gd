@tool
class_name BudgetPolicy
extends Resource

## Per-node modifier budget knobs, factored out of [NodeTypeDef]. v2 promotes
## budget to its own subresource so the same policy can serve many archetypes
## and so the spatial scalar field + per-role bonus compose cleanly with the
## archetype multiplier.
##
## Budget formula:
##   raw      = rng.randi_range(base_min, base_max)
##   scaled   = raw
##            * archetype_multiplier.get(archetype, 1.0)
##            * budget_field.sample(position)
##            * Π role_bonus[t]                for t in role_tags
##   budget   = max(1, round(scaled))
##
## Set [member modifier_pool] on the config and leave [member NodeTypeDef.budget_min]
## / `budget_max` in place — when [GraphProcgenConfig.budget_policy] is non-null
## it overrides the per-type values. Unset = falls back to per-type.

@export var base_min: int = 2
@export var base_max: int = 5

## Per-archetype scale on the rolled budget. Lookups default to 1.0 — list
## only the archetypes you want to depart from baseline.
@export var archetype_multiplier: Dictionary = {}

## Spatial scalar — typically a [RadialGradientField] for "weak center,
## strong rim". Unset = neutral.
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
	var lo := mini(base_min, base_max)
	var hi := maxi(base_min, base_max)
	var raw := float(rng.randi_range(lo, hi))
	var arch_mult := float(archetype_multiplier.get(archetype, 1.0))
	var field_scale := 1.0 if budget_field == null else budget_field.sample(position)
	var role_mult := 1.0
	for t in role_tags:
		if role_bonus.has(t):
			role_mult *= float(role_bonus[t])
	var scaled := raw * arch_mult * field_scale * role_mult
	return maxi(1, int(round(scaled)))
