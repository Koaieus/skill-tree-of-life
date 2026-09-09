@tool
class_name MeleePreview
extends Node2D

## Watches BattleSystem. When the active plan is a valid MeleeAttackPlan,
## mounts a translucent SkillBlade overlaid on the selection and loops the
## swing [method MeleeAttackPlan.resolve] would produce for it. On commit,
## BattleSystem awaits launch() to play the swing live with damage application.
##
## [b]#782: the ghost is a PREDICTION, not a lookalike.[/b] The loop replays the
## trajectory and pop outcome of one real resolve against a shadow world — the
## same [method MeleeAttackPlan._resolve_swing] the authority runs — so the arc
## the player watches, the vertices that go dark and the edges that part are the
## ones the committed swing will produce. Run once per selection change, never
## per cycle. See docs/domain/melee-blade-sim.md.

const _FADE: float = 0.4

@export var battle_system: BattleSystem

## Look profile stamped onto every blade this preview spawns (#256). Null keeps
## [SkillBlade]'s own default. Set here rather than on each blade because the
## preview OWNS blade lifetime — it rebuilds the ghost every cycle, so anything
## written onto a blade from outside is erased on the next rebuild.
@export var blade_style: BladeStyle = null

## Master switch for the IDLE loop only — a committed [method launch] ignores it.
##
## The preview loop is the one part of melee that auto-drives (play → rebuild,
## forever), so anything hosting it needs a way to say "stop": the melee sandbox
## tab drops this the moment its tab loses focus, rather than animating a blade
## behind a hidden panel.
@export var preview_enabled: bool = true:
	set(value):
		if preview_enabled == value:
			return
		preview_enabled = value
		if is_node_ready():
			_refresh()

## A fresh ghost was just built. For surfaces that decorate the live blade (the
## melee sandbox forces vertices de-lit for look tuning) — the preview rebuilds
## on every cycle, so "decorate it once" is never enough.
signal blade_spawned(blade: SkillBlade)

var _ghost: SkillBlade

## The swing clock of the PREDICTION the preview is replaying, or null when the
## swing meets no fortified node. A HANDLE on the live object, never a copy —
## read it for `is_stalled()` / `drag`, never write it. Exists because the melee
## sandbox's stall readout (#780/#781) has nothing else to ask.
##
## [b]#782: this is the resolved swing's clock, at its END state[/b], not a
## per-cycle one being filled in as the ghost animates. The preview no longer
## simulates — it replays [method MeleeAttackPlan.prediction]'s trajectory — so
## there is no per-cycle clock left to watch. The clock's twin, the bunker
## field, is pushed onto the ghost's `state.obstacles` for the same readout.
var last_clock: BladeSwingClock = null
# Generation token so in-flight playback coroutines self-cancel when the
# selection changes underneath them. Bump on every spawn/teardown.
var _gen: int = 0
# True from the first frame of a committed swing until its blade has faded out.
# Gates `_refresh()` — see its docstring for the hang this prevents.
var _live_swing: bool = false

# #504: this class is now PURE ANIMATION — it holds no per-swing bookkeeping
# at all. It used to mirror the applier's accepted set (`_dead_at`,
# `_pending_pops`, `_pending_hits`, read from
# `MeleeAttackPlan.last_live_gate.result`) so it could re-announce damage
# numbers and spike pops on its own replay clock. Both are model facts now,
# emitted where they happen: damage by `SkillNode.take_damage`, the spike pop
# by `BladePopResolver.LiveGate._kill`. The swing and the mutation run
# concurrently on the same `BladeHitEvent.t`, so there is nothing left to
# mirror — and nothing left to go stale.


func _ready() -> void:
	if battle_system != null:
		battle_system.attack_plan_changed.connect(_on_plan_changed)
		battle_system.attack_plan_state_changed.connect(_refresh)


func _on_plan_changed(_plan: AttackPlan) -> void:
	_refresh()


## #504: a COMMITTED swing is not a preview, and must not be refreshable.
##
## The mutation now runs concurrently with the swing, and mutating fires plan
## signals (the forced-dealloc cascade invalidates the plan's own nodes), which
## land here mid-animation. Rebuilding or tearing down the ghost at that moment
## frees the very blade `launch()` is parked on — and a coroutine awaiting a
## freed object is silently dropped, so `launch()` never returns, BattleSystem
## never reaches `_reset()`, and the attack plan is never cleared. That is a
## permanent hang, not a cosmetic glitch.
##
## Before design B the ordering hid this: the whole outcome was applied before
## the replay began, so no cascade signal could arrive mid-swing.
func _refresh() -> void:
	if _live_swing:
		return
	var plan := battle_system.attack_plan
	if preview_enabled and plan is MeleeAttackPlan and plan.is_valid():
		var melee := plan as MeleeAttackPlan
		# #782: the PUSH that keeps the prediction off the repaint path. This is
		# the only surface that wants one, it already knows the selection is
		# valid and the swing is not live, and it runs synchronously inside the
		# `attack_plan_state_changed` dispatch — so the overlay's own repaint,
		# queued in that same dispatch and drawn at frame end, sees the fresh
		# marks. A machine with no preview mounted never calls this and pays
		# nothing, which is the shape `BattleSystem`'s draw-only resolve already
		# wants.
		melee.refresh_prediction()
		_spawn_blade(melee)
		_run_preview_loop(_gen)
	else:
		_teardown()


## The ghost currently mounted, or null. For a sandbox that wants to poke at the
## live blade's visuals (force a vertex de-lit, re-push a [BladeStyle]) or at
## its sim state (#781's strain readout reads `.state.obstacles` off it) —
## nothing in the game reads this.
func current_blade() -> SkillBlade:
	return _ghost


## Pure-animation playback of the swing [BattleSystem] is applying RIGHT NOW.
## Spawns a fresh live blade purely for visuals and plays back
## [member MeleeAttackPlan.last_trajectory] / [member
## MeleeAttackPlan.last_events] — the same scan [method
## MeleeAttackPlan.resolve] ran.
##
## [b]#504: this is concurrent with the mutation, not after it.[/b]
## `BattleSystem.launch_attack` starts this un-awaited and then walks the same
## events on a [BeatClock], landing each hit at its `arrival_time` — which for
## melee is that event's own `BladeHitEvent.t`. So the blade reaching a node
## and the node taking its damage are the same moment, and everything that
## draws (HP bar, shatter, damage number, spike-pop burst) reads the model.
## This class announces nothing; it used to, and that mirror is gone.
##
## Still does NOT rescan, for the reason #474 established: a rescan here would
## re-derive damage from a fresh blade state and drift from what
## [OutcomeApplier] actually lands. Note the old objection to a rescan — that
## it "would run after the depletion cascade" — described replaying a FINISHED
## mutation, which is no longer the shape of this call; the no-rescan rule
## survives on the drift argument alone. #502's landing gate lives in
## [BladeDamageInstance.land_on] and needs nothing from here.
## [param schedule] is the compiled presentation timeline this swing's hits land
## on. It is what the blade's playback rate is DERIVED from (#818): the schedule
## already folds in the player's `combat_time_scale`, and without it the tween
## drew at 1.0 while the hits arrived on a rate-scaled clock — at 2.0x the arc
## finished a full second before the last damage number. Null (a sandbox, a
## test) keeps the authored 1.0 pace.
func launch(plan: MeleeAttackPlan, schedule: OutcomeSchedule = null) -> void:
	_spawn_blade(plan)
	var blade := _ghost
	if blade == null:
		return
	var gen := _gen
	var traj := plan.last_trajectory
	var events := plan.last_events
	# The swing's own pop outcome, so a vertex that dies mid-swing goes de-lit
	# at the `t` it died (#256's interim pop). Read off the plan, never
	# re-derived here — same no-rescan rule the events follow.
	blade.pop_result = plan.last_pops
	# Claim the ghost for the whole swing — set AFTER `_spawn_blade`, which
	# tears the preview loop's blade down, and cleared on every exit below so a
	# early return can't leave previews permanently frozen.
	_live_swing = true
	# Derived, never a second independent number: `blade_playback_rate` owns the
	# inverted-convention arithmetic (schedule multiplies, `play` divides).
	var playback_rate := 1.0
	if schedule != null:
		playback_rate = schedule.blade_playback_rate(MeleeAttackPlan.SWING_DURATION)
	await blade.play(traj, events, false, playback_rate)
	if gen != _gen or blade != _ghost:
		_live_swing = false
		return
	var fade := create_tween()
	fade.tween_property(blade, "modulate", Color(0.55, 0.55, 0.55, 0.0), 0.45)
	await fade.finished
	if blade == _ghost:
		_ghost = null
	blade.queue_free()
	_live_swing = false


func _spawn_blade(plan: MeleeAttackPlan) -> void:
	_teardown()
	_gen += 1
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child(blade)
	var selection: Array[SkillNode] = [plan.source]
	selection.append_array(plan.blade_nodes)
	blade.swing_cw = plan.swing_cw
	if blade_style != null:
		# Before build: `_spawn_visuals` reads the style as it creates the
		# vertices, so a later assignment would repaint rather than author.
		blade.style = blade_style
	blade.build_from_skill_nodes(
			selection, plan.source, plan.get_induced_edges(), plan.attacker)
	_ghost = blade
	blade_spawned.emit(blade)


## Replay the PREDICTED swing, forever, until the selection changes.
##
## [b]#782: this loop no longer simulates.[/b] It used to run its own
## [method SkillBlade.simulate] every cycle, with a fresh drag clock and a fresh
## bunker field — which was both the expensive half of an always-running surface
## and, since #801, wrong: the authoritative resolve REBAKES from each severance
## sample, so a plain sim could not reproduce an arc that loses a vertex partway
## through. Replaying [method MeleeAttackPlan.prediction]'s own trajectory makes
## the ghost arc the resolved arc by construction, drag and stall included, and
## drops the per-cycle sim to nothing.
##
## The front-loading note that "a clock banks what it has touched, so the loop
## must build a fresh one per cycle" is therefore not broken but DISSOLVED:
## there is no per-cycle clock left to bank anything.
##
## What the ghost shows, it shows on the swing's own clock: `pop_result` de-lits
## each doomed vertex AT its pop time rather than pre-greying it, so the player
## watches the spike take it. That is the more informative read, and is the
## choice here — not the ghosting failing to apply.
func _run_preview_loop(gen: int) -> void:
	while gen == _gen and _ghost != null and is_inside_tree():
		var blade := _ghost
		var live_plan := battle_system.attack_plan as MeleeAttackPlan
		if live_plan == null:
			return
		# Warm on the first cycle and a no-op on every later one — the loop
		# outlives the `_refresh` that primed it, and a plan re-validated
		# mid-loop would otherwise replay nothing.
		live_plan.refresh_prediction()
		var prediction := live_plan.prediction()
		if prediction == null or prediction.trajectory == null:
			# No trajectory means no swing to replay. Returning (rather than
			# continuing) is deliberate: `play(null)` finishes instantly, so
			# looping here would spin the frame.
			return
		last_clock = prediction.clock
		# The sandbox's strain readout reads the field off the ghost (#781), and
		# the ghost no longer builds one — hand it the predicted swing's.
		blade.state.obstacles = prediction.obstacles
		blade.pop_result = prediction.pops
		await blade.play(prediction.trajectory, [], true)
		if gen != _gen or _ghost == null:
			return
		var fade := create_tween()
		fade.tween_property(blade, "modulate:a", 0.0, _FADE)
		await fade.finished
		if gen != _gen or _ghost == null:
			return
		# Reset positions for the next cycle. Rebuild is cheap.
		var plan := battle_system.attack_plan as MeleeAttackPlan
		if plan == null or not plan.is_valid():
			return
		var selection: Array[SkillNode] = [plan.source]
		selection.append_array(plan.blade_nodes)
		blade.swing_cw = plan.swing_cw
		blade.build_from_skill_nodes(
				selection, plan.source, plan.get_induced_edges(), plan.attacker)
		blade.modulate.a = 0.35
		# The rebuild freed and recreated every vertex visual, so decoration
		# applied by a listener is gone — same event, same signal.
		blade_spawned.emit(blade)


func _teardown() -> void:
	_gen += 1
	last_clock = null
	if _ghost != null:
		_ghost.stop()
		_ghost.queue_free()
		_ghost = null
