@tool
@abstract
class_name FoldReducer
extends IncidentReducer

## The stock merge-then-fold: [method IncidentReducer._merge_payload_defaults]
## builds the payload (MAX hops, visited union, MAX stack weight, extras), then
## the subclass's [method _fold_damage] decides the one thing a pure fold owns —
## the damage. [FirstReducer], [MaxDamageReducer] and [SumDamageReducer] each
## fix only that; a guard ([CancelIfMultiReducer], [RetractReducer]) overrides
## [method reduce] and calls [code]super[/code].


func reduce(incidents: Array[CastSpell], _cast: PropagationContext) -> CastSpell:
	var merged := _merge_payload_defaults(incidents)
	merged.damage = _fold_damage(incidents)
	return merged


## The resolved damage over [param incidents] (≥1, wave order).
@abstract func _fold_damage(incidents: Array[CastSpell]) -> float
