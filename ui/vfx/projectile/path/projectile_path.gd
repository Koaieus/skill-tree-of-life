@tool
@abstract
class_name ProjectilePath
extends Resource

## How a [Projectile] moves from `origin` to `target` over normalised time.
##
## Pure path-shape — knows nothing about speed, timing, or visuals. The
## [Projectile] driver iterates `t` from 0→1 over its `flight_time` and calls
## [method evaluate] each frame for the world-space position.
##
## Concrete subclasses are Resources so they can be authored as `.tres`,
## inspector-tuned, and shared across attacks. See [BezierArcPath] (default
## quadratic-arc) and [Curve2DPath] (in-editor curve modelling).


## World-space position at normalised time [param t] (0 = origin, 1 = target).
## Implementations should be deterministic and pure — same inputs → same output.
@abstract func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2
