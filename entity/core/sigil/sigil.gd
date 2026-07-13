@tool
@abstract
class_name Sigil
extends Resource

## A core class's identity mark — a parametric 2D shape, sampled as a polygon
## so it can be drawn anywhere a class's emblem needs rendering. The HUD hero
## card ([HeroSigilCard]) is the only consumer today; a [SkillNode] inner-disk
## cutout is a plausible future one, not wired here (its shared batched
## material can't take a per-instance arbitrary shape without breaking
## batching — see `.claude/rules/skill-node-visuals.md`).
##
## [b]Not a Texture.[/b] Parametric so the same resource redraws crisply at
## any radius the consumer picks, and so color/stroke stay the caller's
## choice rather than baked in.

## Whether [method points] traces a closed loop (filled, or ringed) or an open
## path (drawn as a polyline — a spiral doesn't return to its start).
@export var closed: bool = true

## Sample the shape's outline at the given radius, centered on the origin.
@abstract func points(radius: float) -> PackedVector2Array
