class_name SeatMemory
extends RefCounted

## One entity's "last choice" in every attack mode — what the next plan of that
## mode is seeded from and what each tray body reads back on bind. Held per
## entity by [method ArmedStack.memory_for]; machine-local, never synced, never
## saved, and it outlives [method PlayerInputController.clear_transient_state]:
## it is the memory of finished choices, not half-finished intent.

var melee := MeleeMemory.new()
var magic := MagicMemory.new()
var ranged := VolleyPreference.new()
