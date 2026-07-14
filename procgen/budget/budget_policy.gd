@tool
class_name BudgetPolicy
extends Resource

## Per-node modifier budget knobs. A single policy serves every archetype:
## the spatial scalar field + per-role bonus compose cleanly with the
## per-archetype multiplier.
##
## Budget formula:
##   raw     = lerp(base_min, base_max, rng.randf())
##   scaled  = raw
##           * archetype_multiplier.get(archetype, 1.0)
##           * budget_field.sample(position)        if set else 1.0
##           * Π role_bonus[t]                       for t in role_tags
##   budget  = max(1, round(scaled))
##
## One range (`base_min`/`base_max`), one positional lever (`budget_field`).
## The radial shape lives in `budget_field`: a [RadialGradientField] scaling the
## rolled range up toward the rim gives the same no-dead-nodes property a
## floor/ceiling split would (outer_min = base_min × outer_scale can exceed
## inner_max = base_max × inner_scale) without a second field to keep in sync.
##
## Assigned to [member GraphProcgenConfig.budget_policy]; unset there means
## every node rolls a budget of 0 (no modifiers).

@export var base_min: int = 2
@export var base_max: int = 5

## Per-archetype scale on the rolled budget. Lookups default to 1.0 — list
## only the archetypes you want to depart from baseline.
@export var archetype_multiplier: Dictionary = {}

## Positional multiplier on the rolled range — the radial-shape lever. Typically
## a [RadialGradientField] scaling budget up toward the rim. Unset = neutral.
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
	return compute_budget_breakdown(archetype, position, role_tags, rng).budget as int


## Same roll as [method compute_budget], but returns every factor that went
## into it instead of just the final int — used by the procgen playground
## (#166) to show a designer *why* a sample landed where it did, not just the
## number. `compute_budget` calls this and discards everything but `budget` so
## the two never drift and the RNG is drawn exactly once either way.
func compute_budget_breakdown(
		archetype: StringName,
		position: Vector2,
		role_tags: Array,
		rng: RandomNumberGenerator,
) -> Dictionary:
	var raw := lerpf(float(base_min), float(base_max), rng.randf())
	var arch_mult := float(archetype_multiplier.get(archetype, 1.0))
	var field_scale := 1.0 if budget_field == null else budget_field.sample(position)
	var role_mult := 1.0
	for t in role_tags:
		if role_bonus.has(t):
			role_mult *= float(role_bonus[t])
	var scaled := raw * arch_mult * field_scale * role_mult
	var budget := maxi(1, int(round(scaled)))
	return {
		"raw": raw,
		"base_min": base_min,
		"base_max": base_max,
		"arch_mult": arch_mult,
		"field_scale": field_scale,
		"role_mult": role_mult,
		"budget": budget,
	}
