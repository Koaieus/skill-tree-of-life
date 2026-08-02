@tool
@abstract
class_name HopDamage
extends Resource

## Per-hop damage ramp — plugs into [member PropagationConfig.hop_damage].
## Called once per propagation step with the parent's damage and hop_index,
## returns the child's damage.
##
## Replaces the bare [code]damage_multiplier_per_hop[/code] float so a spell
## can express any of: multiplicative falloff (Lightning), additive ramp
## (Trailblazer / Resonator (#352)), affine (both), or an arbitrary
## expression — without sub-classing [PropagationStep]. Mirrors the
## [code]StatFormula[/code] pattern in the stats system and the
## [PropagationFilter] / [IncidentReducer] / [CritCondition] pattern here.
##
## The signature takes [param hop_index] so future back-loaded curves (ramp
## scales with depth) are expressible without an API change. Stock ramps
## (Multiply / Add / Affine) ignore it; ExpressionRamp exposes it as an
## identifier. See #351 fork 2.
##
## Order of operations for the affine case is [code](d + a) × m[/code]
## (add-then-scale), matching Trailblazer's historical
## [code]accumulated = payload.damage + per_hop_increment[/code] then
## slam-multiply. See #351 fork 1.


@abstract func apply(damage: float, hop_index: int) -> float


func get_description() -> String:
	return ""