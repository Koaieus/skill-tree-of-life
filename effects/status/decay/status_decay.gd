@abstract
class_name StatusDecay
extends Resource

## How a [StatusDef]'s power falls each tick — the swappable decay slot,
## [member StatusDef.decay]. A member answers [method decayed] (one tick's
## arithmetic) and [method describe] (the "-N per turn" clause of
## [method StatusDef.get_description]).
##
## SHARED and STATELESS: one instance is referenced by every node carrying
## the status, the shadow world's included, so a member holds knobs only —
## never per-node state (the same gotcha as [ArmorBreakStatus]).
##
## A new shape is a sibling script extending this one with its own knobs.


## The power left after one tick's decay of [param power]. `0` means removed.
@abstract func decayed(power: float) -> float


## The per-turn clause for a derived description, e.g. `"-1 per turn"`.
@abstract func describe() -> String
