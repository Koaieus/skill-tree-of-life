class_name MeleeMemory
extends RefCounted

## An entity's melee "last choice" (see [SeatMemory]).

## The last launched blade, as [method MeleeAttackPlan.to_dict] wrote it
## (stable ids + `swing_cw`) — what Reform rebuilds. Empty until a launch.
## Kept as stable ids so a member gone from the board refuses the reform rather
## than shrinking the blade.
var reform_slot: Dictionary = {}

## Sticky swing direction for the next [MeleeAttackPlan]
## ([member MeleeAttackPlan.swing_cw]); survives resets and re-arms.
var next_swing_cw: bool = false
