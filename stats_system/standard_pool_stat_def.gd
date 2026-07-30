@tool
class_name StandardPoolStatDef
extends PoolStatDef

## A fixed-cap pool (HP, mana, action points, deallocation points, …).
## The cap moves only via the modifier pipeline; this class adds the
## optional "heal current to follow a cap rise" behaviour.

## When the modifier-driven cap rises, bump `current` by the same delta so the
## relative fill stays the same. Off = a raw cap raise leaves current put
## (the bar looks emptier).
@export var heal_on_max_increase: bool = true


func on_max_increased(stat: PoolStat, delta: float) -> void:
	if heal_on_max_increase:
		grant_max_increase_delta(stat, delta)


## Grant a cap rise straight into `current` — **the D-21 ratchet**, and the one
## place to change it.
##
## On `health` this is knowingly exploitable: allocating a big-CON node raises
## the cap and hands you the delta as HP immediately, so a player can cycle
## territory to heal. D-21 accepts that — engineering your graph to move your
## numbers is legitimate play in a game where the skill graph *is* the
## mechanics; the bar is "doesn't make it too easy", not "loophole-free". The
## exploit is bounded because DP is not free, and it is capped on the infinite
## version by [code]deallocation_points[/code] setting
## [member heal_on_max_increase] to `false` — a node granting +1 max DP raises
## the maximum without handing over a spendable point.
##
## D-26 requires this to stay a single named method, never inlined into an
## allocation path, so that when the ratchet is revisited the toggle is
## findable. The recorded-but-not-adopted alternative is the voluntary/forced
## dealloc split — see D-21/D-26 in docs/design/mvp_decisions.md.
func grant_max_increase_delta(stat: PoolStat, delta: float) -> void:
	stat.set_current(stat.current + delta)
