@tool
class_name MeleePreview
extends Node2D

## Watches BattleSystem. When the active plan is a valid MeleeAttackPlan,
## mounts a translucent SkillBlade overlaid on the selection and loops the
## same swing sim that resolve() runs. On commit, BattleSystem awaits
## launch() to play the swing live with damage application.

const _FADE: float = 0.4

@export var battle_system: BattleSystem

## Master switch for the IDLE loop only — a committed [method launch] ignores it.
##
## The preview loop is the one part of melee that auto-drives (simulate → play →
## rebuild, forever), so anything hosting it needs a way to say "stop": the melee
## sandbox tab drops this the moment its tab loses focus, rather than burning a
## swing sim per frame behind a hidden panel.
@export var preview_enabled: bool = true:
	set(value):
		if preview_enabled == value:
			return
		preview_enabled = value
		if is_node_ready():
			_refresh()

var _ghost: SkillBlade
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
		_spawn_blade(plan as MeleeAttackPlan)
		_run_preview_loop(_gen)
	else:
		_teardown()


## The ghost currently mounted, or null. For a sandbox that wants to poke at the
## live blade's visuals (force a vertex de-lit, re-push a [BladeStyle]) — nothing
## in the game reads this.
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
func launch(plan: MeleeAttackPlan) -> void:
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
	await blade.play(traj, events, false)
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
	blade.build_from_skill_nodes(
			selection, plan.source, plan.get_induced_edges(), plan.attacker)
	_ghost = blade


func _run_preview_loop(gen: int) -> void:
	while gen == _gen and _ghost != null and is_inside_tree():
		var blade := _ghost
		var traj := blade.simulate(MeleeAttackPlan.SWING_DURATION)
		await blade.play(traj, [], true)
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


func _teardown() -> void:
	_gen += 1
	if _ghost != null:
		_ghost.stop()
		_ghost.queue_free()
		_ghost = null
