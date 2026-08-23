class_name RouteProbeGameRoot
extends GameRoot

## A [GameRoot] that counts departures instead of taking them (#526).
##
## `route_to_meta_now()` ends the [GameSession] and hands the tree to
## [SceneDirector], which would swap GUT's own scene out mid-suite. Overriding
## the last step is what lets a test assert the parts that actually carry the
## rules — the once-only latch and the `route_to_meta_on_run_end` veto — on the
## real production path rather than on a re-implementation of it.
##
## Lives in `test/fixtures/` (outside `.gutconfig.json`'s `dirs`), so GUT never
## tries to run it as a test script.

var departures: int = 0


func _leave_for_meta() -> void:
	departures += 1
