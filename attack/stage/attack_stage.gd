class_name AttackStage
extends Node

## The seam between [BattleSystem]'s launch path and whatever DRAWS an attack.
## Sim-side and deliberately inert: every method is a no-op default, so a null
## stage, an unset one and this base class all behave as a headless peer does —
## no wind-up seconds, nothing played, nothing held. The real one is
## `AttackPresenter` under `presentation/`, which this layer never names.
##
## [b]Animation never gates the mutation loop.[/b] [method play] is called
## un-awaited; [BattleSystem] waits on [signal finished] only AFTER the world
## has finished applying, and only when [method holds_release] says so. The
## reveal clock (the [BeatClock] the wind-up seconds are waited out on) stays
## in [BattleSystem] — a stage returns seconds, it never waits them.
##
## Call order per launch: [method mount] → [method begin_windup] →
## [method play] → [method holds_release] → [method unmount].
## [method prepare_replay] runs before all of them, on a mirror only.

## Emitted when a [method play] that [method holds_release] reported as
## holding has finished. Never emitted for a play that does not hold.
signal finished


## A mirror is about to commit [param plan], decoded off the wire — start any
## draw-only re-simulation the replay will need. Never mutates.
func prepare_replay(_plan: AttackPlan) -> void:
	pass


## Called at commit, BEFORE [signal BattleSystem.attack_committed], so
## [method focus] already answers when the director reads it there.
func mount(_plan: AttackPlan, _outcome: AttackOutcome) -> void:
	pass


## Stage [param plan]'s wind-up on [param tempo] and return the seconds it
## takes. The caller waits those seconds on its own clock.
func begin_windup(_plan: AttackPlan, _tempo: PresentationTempo) -> float:
	return 0.0


## True when [method play] will draw [param plan] — the caller compiles the
## schedule and announces [signal BattleSystem.attack_replay_started] only then.
func stages(_plan: AttackPlan) -> bool:
	return false


## Draw the replay. Called un-awaited: it runs synchronously up to its first
## await, so an implementation that holds must latch its holding state before
## that await (see [method holds_release]).
func play(_plan: AttackPlan, _outcome: AttackOutcome) -> void:
	pass


## True while the [method play] in flight holds the launch's release — melee's
## swing, whose plan must stay live until the blade is done. Asked right after
## [method play] returns control, and again after the world has applied.
func holds_release(_plan: AttackPlan) -> bool:
	return false


## The node the camera frames for the launch in flight (it answers
## `focus_marker()` / `focus_marker_changed`), or null.
func focus() -> Node:
	return null


## The launch released; drop whatever [method mount] held.
func unmount() -> void:
	pass
