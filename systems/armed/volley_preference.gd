class_name VolleyPreference
extends RefCounted

## An entity's ranged "last choice" (see [SeatMemory]): sticky for the run.

## Card order of the ammo types, by type id. Empty means the roster's order.
var order: Array[StringName] = []
## Whether base arrows fill the volley up to N.
var fill: bool = true
## Special counts `{type_id: n}` — the last setting per special, re-clamped to
## the bins on every compose.
var special_counts: Dictionary[StringName, int] = {}
