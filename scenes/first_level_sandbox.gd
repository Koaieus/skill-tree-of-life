extends "res://scenes/procgen_play_sandbox.gd"

## The first level, and — for now — the scene you launch directly to play it.
##
## It exists as its own script for the second of those two jobs. #584 splits the
## shipped level from its sandbox properly; until then this subclass is where
## sandbox-only behaviour goes, so the shared level script above stays the one
## that merely CONSUMES [member GameSession.roster].
##
## What it overrides is one method: the camp shape of the fallback roster, the
## one [method _setup_level] invents when no lobby ran.
##
## [b]Why one knob and not two.[/b] #553 made the roster decide how many
## contenders exist, which retired [member n_random_starters] as the opponent
## count on the legacy generation path — it is recomputed from the roster there.
## That left this scene with two exports that both read as "how many enemies":
## a dead one at 5 and a live [member camp_sizes] at [1, 1]. The inspector said
## five and the map had one. Deriving the shape from [member n_random_starters]
## collapses them back into a single knob.
##
## The name stays literally true, which is why it is the one that survives:
## `first_level.tres` authors exactly one starting point and camp 0 is exactly
## one human, so "N random starters beyond the authored core" and "N AI
## opponents" are the same number — [method _setup_level] recomputes
## `cfg.n_random_starters` as `contenders - authored` and lands back on the
## value written here.

func _fallback_camp_sizes() -> Array[int]:
	var shape: Array[int] = [1, maxi(0, n_random_starters)]
	return shape
