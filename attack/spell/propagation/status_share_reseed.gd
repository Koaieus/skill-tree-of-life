@tool
class_name StatusShareReseed
extends ScalarReseed

## Reseeds a [CarriedScalar] to [member share] × the landed node's stacks of
## [member status_id], read after this wave landed — so the carried value is
## re-read at every arrival from what is there now (pre-existing stacks and a
## crit's doubling included), never carried forward from the parent's value.

## The status whose stacks are re-read.
@export var status_id: StringName = &""
## The fraction of those stacks carried onward. Tentative, easy to change.
@export_range(0.0, 1.0, 0.05, "or_greater") var share: float = 0.5


func reseed(_value: float, lctx: LandingContext, _scalar: CarriedScalar) -> float:
	if lctx == null or lctx.cast == null:
		return 0.0
	return share * lctx.stacks_of(lctx.node, status_id)
