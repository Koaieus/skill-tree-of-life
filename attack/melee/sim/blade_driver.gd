@abstract
class_name BladeDriver
extends RefCounted

## Abstract base — prescribed kinematic motion for one or more particles.
## Called after Verlet integration each sim step; overrides positions.
## Drivers are how the swing happens — kinematic prescribed motion for
## select particles, everything else follows via constraints.

@abstract func apply(positions: PackedVector2Array, t: float) -> void
