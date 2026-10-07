class_name ArrowImpactContext
extends RefCounted

## What an arrow's parts may know about where it landed, handed over by
## [ArrowVolleyCoordinator] once the landing's verdict is in. Parts read only
## this — never a [SkillNode] — so a part is testable with a hand-built
## context and a peer draws what the host drew.
##
## A context with no riders is a plain impact; a part spreading over riders
## then plays nothing extra.

## World position of the target node's centre.
var position: Vector2 = Vector2.ZERO
## The target node's grown radius ([member SkillNode.radius]), world pixels.
var radius: float = 0.0
## World positions of this arrow's non-dud riders' targets, in hit order.
var rider_positions: PackedVector2Array = PackedVector2Array()
