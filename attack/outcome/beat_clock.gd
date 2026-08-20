class_name BeatClock
extends RefCounted

## The mutation loop's own clock (#504, design B). [OutcomeApplier] awaits this
## between landings, so an attack's world mutation happens at each hit's
## [member HitInstance.arrival_time] — the same clock the player is watching.
## There is no view store and no second source of truth: what is drawn is the
## model, at every beat.
##
## [b]This is not the disease #474 cured.[/b] The rule is
## [b]never frame-ordered mutation[/b] — NOT "never mutate inside an await".
## `await attack_vfx.play(...)` orders mutation by [i]animation completion[/i],
## so a lag spike, a muted animation or a dropped frame changes gameplay; that
## stays gone. Awaiting a [i]fixed logical interval owned by the mutation loop[/i]
## is a different mechanism: the game is turn-based,
## [member BattleSystem.is_launching] guards reentrancy, and nothing else acts
## inside the window — so only [i]order[/i] is observable, and order is
## code-order. The over-broad phrasing is what drove five rounds of latches
## (#479/#481/#482/#483/#485/#487). See docs/domain/presentation-clock.md.
##
## The intermediate state is [b]valid, not torn[/b]: it is the exact sequence of
## states the code already walked through at t=0 — hit lands, node depletes,
## cascade deallocs, modifiers revoke — one beat at a time.

## The AUTHORED time the loop has walked to — the `arrival_time` of the last
## landing, not wall-clock time since launch. The two coincide on an
## uninterrupted real-clock run and deliberately do not otherwise: an instant
## clock advances this without waiting at all, and [method drain] lands the
## remainder immediately while this still reports each hit's authored slot.
## It exists to compute the delta between beats, nothing more. Only ever
## advances.
var elapsed: float = 0.0

## When true, [method advance_to] returns without waiting and the loop drains
## synchronously. This is the whole mitigation for design B's one real risk —
## a mutation loop interrupted mid-window would otherwise leave the remaining
## hits permanently unlanded, a world that is valid but wrong. It doubles as
## the test mode, which is what keeps tests that read world state on the line
## after `launch_attack` passing unmodified.
var instant: bool = false

var _tree: SceneTree = null

## Emitted when a real wait elapses, or when [method drain] cuts it short.
## Private plumbing: [method advance_to] parks on this rather than on the timer
## directly, so a drain can release a parked loop that would otherwise wait for
## a timer belonging to a tree that is going away.
signal _beat_reached


## A clock with no tree: every [method advance_to] is a no-op, so the applier
## runs start-to-finish synchronously. The default for tests and for any
## headless caller.
static func instant_clock() -> BeatClock:
	var clock := BeatClock.new()
	clock.instant = true
	return clock


## A clock that really waits, on [param tree]'s timers.
static func for_tree(tree: SceneTree) -> BeatClock:
	var clock := BeatClock.new()
	clock._tree = tree
	clock.instant = tree == null
	return clock


## Wait until [param t] seconds after the attack began. Hits arrive in
## ascending `arrival_time` order, so the wait is the delta since the last
## beat; a non-monotonic or already-passed `t` costs nothing.
func advance_to(t: float) -> void:
	var wait: float = t - elapsed
	elapsed = maxf(elapsed, t)
	if instant or _tree == null or wait <= 0.0:
		return
	# Park on `_beat_reached`, not on the timer — see the signal's docstring.
	var timer := _tree.create_timer(wait)
	timer.timeout.connect(func() -> void:
		if not instant:
			_beat_reached.emit(),
			CONNECT_ONE_SHOT)
	await _beat_reached


## Stop waiting: release a parked loop and make every remaining
## [method advance_to] a no-op, so the rest of the attack lands synchronously.
## Idempotent. Called on scene teardown ([method GameRoot._exit_tree]).
##
## The release is synchronous — the parked loop resumes and runs to completion
## inside this call — which is what makes this usable from `_exit_tree`, where
## the nodes being mutated are still alive.
func drain() -> void:
	if instant:
		return
	instant = true
	_beat_reached.emit()
