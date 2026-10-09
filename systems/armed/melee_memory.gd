class_name MeleeMemory
extends RefCounted

## An entity's melee "last choice" (see [SeatMemory]).

## The last blade this entity successfully launched, in the plan's own wire
## form ([method MeleeAttackPlan.to_dict]) so there is no second representation
## of a blade; only the stable ids and `swing_cw` are read back out, and a
## member gone from the board refuses the reform rather than shrinking the
## blade. Empty until a launch. Reform is not a command: it expands into an
## ordinary [MeleeAttackPlan] that launches through the normal path, so it adds
## no wire surface (docs/domain/multiplayer-sync-model.md).
var reform_slot: Dictionary = {}

## Sticky swing direction for the next [MeleeAttackPlan]
## ([member MeleeAttackPlan.swing_cw]); survives resets and re-arms.
var next_swing_cw: bool = false
