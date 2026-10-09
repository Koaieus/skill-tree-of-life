class_name VolleyPreference
extends RefCounted

## An entity's ranged "last choice" (see [SeatMemory]): sticky for the run.

## Card order of the ammo types, by type id — the volley's FIRING order: the
## ranged body lists [member RangedAttackPlan.ammo] in it, types missing here
## following in roster order. Empty means the roster's order
## ([method AmmoTypeRoster.sorted]), which is also what restore-default writes.
var order: Array[StringName] = []
## Whether base arrows fill the volley up to N.
var fill: bool = true
## Special counts `{type_id: n}` — what the player chose per special. Clamped
## to the bins in the composed plan only; a launch that empties a bin leaves
## the choice here untouched.
var special_counts: Dictionary[StringName, int] = {}
