@tool
class_name WeightProfile
extends Resource

## Abstract base for the procgen weight pipeline. Each concrete profile
## returns a multiplier to apply to an entry's base weight, given a
## per-node [WeightContext]. The procgen modifier pass walks an
## `Array[WeightProfile]`, multiplying contributions together.
##
## Profiles can return 0.0 to drop an entry (CollisionProfile does this).
## Negative returns are clamped to 0.
##
## Subclasses override [method multiplier_for].

func multiplier_for(_entry: ModifierPoolEntry, _context: WeightContext) -> float:
	return 1.0
