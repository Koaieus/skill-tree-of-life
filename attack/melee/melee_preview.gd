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

## Trajectory samples the aim-time prediction resolves per frame (#821).
##
## A melee resolve is a ~72 sample physics scan; run whole it is a multi-frame
## stall on the one input the player is watching for an answer to. Stepping it
## trades a finished arc later for a partial arc NOW — the picture the player
## actually wants while still choosing nodes ("roughly where does this go").
##
## The knob is per FRAME, not per click: whatever the blade's size, the stall a
## click costs is one budget's worth of samples, and a bigger blade simply takes
## more frames to finish. Raising it shortens the wait for the full arc and
## lengthens the worst frame; 0 or less resolves the whole swing in one frame,
## which is the pre-#821 behaviour.
@export var prediction_slice_steps: int = 12

## Trajectory samples a MIRROR's committed-swing draw-only resim steps per
## frame (#796) — same shape as [member prediction_slice_steps], different
## consumer. That one exists so an AIMING click never stalls; this one exists
## so a COMMITTED swing's resim never bakes whole before [method launch] can
## start drawing it. Kept as its own knob rather than reusing the aim-time one
## because the two have different windows to finish in: the aim-time one only
## has to finish "soon" after a click, this one only has to stay ahead of
## [method launch]'s own playback — see [method MeleeAttackPlan.replay_duration].
@export var replay_slice_steps: int = 12

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
## per-cycle one being filled in as the ghost animates. (#821 qualifies that
## by exactly one window: while the prediction is still being sliced the clock
## is at the end of the samples resolved SO FAR, and reaches the swing's end
## when the last slice lands.) The preview no longer
## simulates — it replays [method MeleeAttackPlan.prediction]'s trajectory — so
## there is no per-cycle clock left to watch. The clock's twin, the bunker
## field, is pushed onto the ghost's `state.obstacles` for the same readout.
var last_clock: BladeSwingClock = null
# The blade [method begin_windup] claimed for the committed swing, or null when
# no wind-up staged one. What makes [method launch] a HANDOFF rather than a
# re-spawn (#559 decision 2).
var _windup_blade: SkillBlade = null
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
	# Idle costs nothing: `_process` is the #821 slice pump and is armed only
	# while a prediction is actually part-way resolved.
	set_process(false)
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
		#
		# #821: one SLICE of it, not the whole resolve. The click gets a
		# partial arc in this very frame and `_process` extends it; the plan's
		# own invalidation cancels an in-flight run, so a click landing
		# mid-slice can never be answered with the previous selection's swing.
		_pump_prediction(melee)
		_spawn_blade(melee)
		_run_preview_loop(_gen)
	else:
		set_process(false)
		_teardown()


## Resolve one frame's worth of the aim-time prediction, and keep `_process`
## running exactly while there is more to do.
##
## The budget is spent per FRAME, which is the whole point (#821 decision 5):
## no single frame blocks, regardless of blade size.
func _pump_prediction(plan: MeleeAttackPlan) -> void:
	var complete := plan.advance_prediction(prediction_slice_steps)
	set_process(not complete)


## Start a MIRROR's committed-swing draw-only resim (#796) and arm the frame
## pump that steps it. Called by [BattleSystem] the moment a REPLAY command's
## record lands — well before [method begin_windup] / [method launch] run —
## so the wind-up's own seconds are free head start on top of whatever
## [member replay_slice_steps] buys per frame.
##
## [param substeps] / [param enable_length_scaling] are the peer sim-fidelity
## graphics setting: draw-only per ADR 0002, so degrading them costs nothing
## real. Idempotent — see [method MeleeAttackPlan.begin_replay_resolve].
func begin_replay(plan: MeleeAttackPlan, substeps: int, enable_length_scaling: bool) -> void:
	plan.begin_replay_resolve(substeps, enable_length_scaling)
	set_process(true)


## The slice pump. Deliberately NOT the preview loop — that loop is parked on
## `blade.play` for the length of a swing cycle, which is exactly the window
## the prediction has to finish inside.
func _process(_delta: float) -> void:
	if battle_system == null:
		set_process(false)
		return
	var replay_plan := battle_system.attack_plan as MeleeAttackPlan
	if replay_plan != null and replay_plan.is_replaying():
		# #796: a committed swing's resim keeps stepping regardless of
		# `_live_swing` / `preview_enabled` — [method launch]'s docstring
		# already establishes both are ignored for a committed swing, and this
		# is what [method launch] is waiting on.
		var complete := replay_plan.advance_replay_resolve(replay_slice_steps)
		set_process(not complete)
		return
	if _live_swing or not preview_enabled:
		set_process(false)
		return
	var plan := battle_system.attack_plan as MeleeAttackPlan
	if plan == null or not plan.is_valid():
		set_process(false)
		return
	_pump_prediction(plan)


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
	# #559 decision 2: [method begin_windup] already claimed the ghost the
	# player has been watching and formed it back up, so the live swing takes
	# it over as-is. A caller that skipped the wind-up entirely (a sandbox, a
	# fixture calling `launch` straight) still gets one spawned here.
	if _windup_blade == null or _windup_blade != _ghost:
		_spawn_blade(plan)
	_windup_blade = null
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
	# #796: a MIRROR's resim may still be stepping — `plan.replay_duration()`
	# is the swing's real trajectory-time span either way (in flight or
	# already finished; see its docstring), so `play` always sizes its tween
	# correctly rather than reading a partial `traj.duration()`.
	await blade.play(traj, events, false, playback_rate, plan.replay_duration())
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


## Stage the wind-up for a swing that has just committed, and return the
## seconds it occupies (0.0 when every beat is zero-length). Called by
## [method BattleSystem._commit] BEFORE [method launch], and never awaited —
## [BattleSystem] waits out the returned length on its own beat clock, so no
## animation gates the mutation loop (`.claude/rules/presentation-clock.md`).
##
## [b]This is a HANDOFF, never a re-predict (#559 decision 2).[/b] The ghost
## the player has been watching loop is CLAIMED rather than rebuilt: nothing
## here calls [method MeleeAttackPlan.refresh_prediction], so
## [member MeleeAttackPlan.prediction_runs] cannot move during a launch. With
## #782 the ghost is already a real resolve of the current world and the
## authority re-resolved at submit; a third resolve of the same swing would buy
## nothing and cost a frame hitch.
##
## [param seated] collapses every beat to zero — [b]the sequence still runs[/b].
## #559's sharpening on decision 1: gating the sequence itself on the seat
## predicate would delete the await point #796 needs on the one machine that is
## typically the authority. The seated path is literally acceptance 5's
## escape-hatch configuration, not a separate code path.
func begin_windup(plan: MeleeAttackPlan, tempo: PresentationTempo,
		seated: bool) -> float:
	if plan == null:
		return 0.0
	if _ghost == null:
		_spawn_blade(plan)
	else:
		# Cancel the preview loop's in-flight coroutine (it re-checks `_gen`
		# after every await) and put the SAME SkillBlade back at rest, rather
		# than freeing the one the player is looking at and instancing another.
		_gen += 1
		_ghost.stop()
		_rebuild_blade(_ghost, plan)
	var blade := _ghost
	if blade == null:
		return 0.0
	# Claim the ghost for the whole commit — from here until `launch` releases
	# it, `_refresh` must not tear it down (see that method's docstring: a
	# freed blade under an awaiting coroutine is a permanent hang).
	_live_swing = true
	_windup_blade = blade
	blade.modulate = Color.WHITE
	if seated or tempo == null:
		blade.form_instantly()
		return 0.0
	return blade.form_in(tempo.melee_windup_lead(), tempo.melee_windup_form_span,
			tempo.melee_windup_stamp_time, tempo.melee_windup_glow_ramp,
			tempo.melee_windup_flare)


## Re-author an EXISTING blade from [param plan]'s current selection, resetting
## every vertex to its rest position. Shared by the preview loop's per-cycle
## reset and by [method begin_windup]'s claim — one implementation, so the two
## cannot drift on what "back to rest" means.
func _rebuild_blade(blade: SkillBlade, plan: MeleeAttackPlan) -> void:
	var selection: Array[SkillNode] = [plan.source]
	selection.append_array(plan.blade_nodes)
	blade.swing_cw = plan.swing_cw
	blade.build_from_skill_nodes(
			selection, plan.source, plan.get_induced_edges(), plan.attacker)
	# The rebuild freed and recreated every vertex visual, so decoration
	# applied by a listener is gone — same event, same signal.
	blade_spawned.emit(blade)


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
		_pump_prediction(live_plan)
		# #821: the PARTIAL is a valid picture. `SkillBlade.play` reads the
		# sample count once, at the top, so a cycle started mid-slice arcs as
		# far as the prediction had got and the NEXT cycle — a swing plus a fade
		# later, by which time the slices are long done — arcs the whole way.
		var prediction := live_plan.prediction_partial()
		if prediction == null or prediction.trajectory == null \
				or prediction.trajectory.samples.size() < 2:
			# No trajectory means no swing to replay. Returning (rather than
			# continuing) is deliberate: `play(null)` finishes instantly, so
			# looping here would spin the frame — and so would a one-sample
			# trajectory, whose duration is zero.
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
		_rebuild_blade(blade, plan)
		blade.modulate.a = 0.35


func _teardown() -> void:
	_gen += 1
	last_clock = null
	_windup_blade = null
	if _ghost != null:
		_ghost.stop()
		_ghost.queue_free()
		_ghost = null
