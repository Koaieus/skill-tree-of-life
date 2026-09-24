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

## Every tween handed out that may still be alive; pruned on [method tween]
## (production never advances, so a long-lived host would otherwise accumulate
## every tween it ever played) and on [method advance].
var _live: Array[Tween] = []


## `host.create_tween()`, tracked, paused when [member manual]. Chain on the
## returned tween exactly as on a bare one.
func tween(host: Node) -> Tween:
	_prune()
	var tw := host.create_tween()
	if manual:
		tw.pause()
	# A tween finished by custom_step stays is_valid() until the tree next reaps
	# it, and a paused one never reads is_running() — so finishing is heard.
	tw.finished.connect(func() -> void: _live.erase(tw), CONNECT_ONE_SHOT)
	_live.append(tw)
	return tw


## Step every live tween by [param delta] seconds, in creation order, dropping
## the ones that have finished or been killed. A no-op on the real clock is not
## its job: callers only step in [member manual] mode.
##
## Iterates a snapshot: a tween a callback creates mid-step is first moved by the
## NEXT advance, as a tween born on real frame N first moves on N+1.
## [method Tween.custom_step]'s return is not a finished test (it stays true on
## the finishing step) — a killed tween is dropped on [method Tween.is_valid], a
## finished one on its [signal Tween.finished].
##
## [b]Step past a boundary, not onto it.[/b] A step whose delta lands exactly on
## the end of a tweener stops there with nothing left over, so the tweener
## after it (a callback included) waits for the next step. Advance by the
## schedule's number plus a hair, or advance again.
func advance(delta: float) -> void:
	for tw in _live.duplicate():
		if tw.is_valid():
			tw.custom_step(delta)
	_prune()


## Kill every live tween. For a consumer's own teardown / re-arm paths.
func kill_all() -> void:
	for tw in _live:
		if tw.is_valid():
			tw.kill()
	_live.clear()


## How many tweens are tracked and still alive — the clock's own observable.
func live_count() -> int:
	_prune()
	return _live.size()


func _prune() -> void:
	_live = _live.filter(func(tw: Tween) -> bool: return tw.is_valid())
