@tool
class_name SplashEffect
extends OnHitEffect

## Stub — filled in by the next commit.

enum Reach { TARGET_AND_HOSTILE_NEIGHBOURS }

@export var inner: OnHitEffect = null
@export var reach: Reach = Reach.TARGET_AND_HOSTILE_NEIGHBOURS


func apply(landing: HitLanding) -> void:
	if inner != null:
		inner.apply(landing)
