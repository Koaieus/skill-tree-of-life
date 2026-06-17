@abstract
class_name BladeConstraint
extends RefCounted

## Abstract base — a single PBD constraint, projected each solver iteration.
## Mutate `positions` in place to satisfy the constraint. Order-independent
## at the limit: more iterations = closer to satisfied.

@abstract func project(
		positions: PackedVector2Array,
		inv_masses: PackedFloat32Array) -> void
