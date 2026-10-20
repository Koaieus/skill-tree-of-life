@tool
@abstract
class_name ScalarReseed
extends Resource

## The optional reseed hook of a [CarriedScalar]: called in its mint with the
## landing context, BEFORE the scalar's progression applies, it may replace the
## carried value from the landed world. The mint runs after the wave landed, so
## [param lctx] reads this wave's stacks and damage.
@abstract func reseed(value: float, lctx: LandingContext, scalar: CarriedScalar) -> float
