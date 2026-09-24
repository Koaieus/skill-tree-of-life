class_name TweenClock
extends RefCounted

## The one door through which a tween-driven controller creates its tweens, so
## a unit test can step them by hand (#992: docs/domain/testing-tiers.md §3).
##
## Production leaves [member manual] false and the tweens run on the real clock
## exactly as a bare `create_tween()` would. A test flips [member manual] before
## the first tween exists: every tween is then created paused and only
## [method advance] moves it — through [method Tween.custom_step], so
## `tween_property`, `tween_interval` and `tween_callback` fire in order at the
## exact stepped instant, and two real frames later nothing has moved.
##
## This is the tween consumer's twin of [BeatClock] (awaits) and of
## [method LevelUpFlourish.advance] (a hand-rolled countdown): three clocks
## because three consumers, one rule — the controller advances on delta, never
## on a clock only the wall can move. Consumers hold it as a public
## `var clock := TweenClock.new()`; a test writes `x.clock.manual = true` and
## steps `x.clock.advance(dt)`. Reaching into `x._some_tween` instead is the
## §8 reach-in this class exists to delete.

## When true, tweens from [method tween] are created paused; [method advance]
## is the only thing that moves them. Set before the first tween is created.
var manual: bool = false

## Every tween handed out that may still be alive; pruned on [method advance].
var _live: Array[Tween] = []


## `host.create_tween()`, tracked, paused when [member manual]. Chain on the
## returned tween exactly as on a bare one.
func tween(host: Node) -> Tween:
	return null


## Step every live tween by [param delta] seconds, in creation order, dropping
## the ones that have finished or been killed. A no-op on the real clock is not
## its job: callers only step in [member manual] mode.
func advance(delta: float) -> void:
	pass


## Kill every live tween. For a consumer's own teardown / re-arm paths.
func kill_all() -> void:
	pass


## How many tweens are tracked and still alive — the clock's own observable.
func live_count() -> int:
	return 0
