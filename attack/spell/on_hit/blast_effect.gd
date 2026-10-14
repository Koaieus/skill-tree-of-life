@tool
class_name BlastEffect
extends SplashEffect

## The explosion: a [SplashEffect] preset that never lands on its centre (the
## centre already took the main hit) and inherits its landing's
## [member HitLanding.target_mask] — an arrow's blast hits what an arrow may, a
## spell's what its targeting may. Its reach is [member range_finder]'s, built
## by whoever emits it; one finder per distinct radius keeps
## [member HitLanding.gather_cache] deduping a volley. A named type because
## every Explosive emitter instances it.


func _init() -> void:
	hits_centre = false
	ownership_filter = 0
