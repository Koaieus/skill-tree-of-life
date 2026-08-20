class_name MeleePreview
extends Node2D

## Watches BattleSystem. When the active plan is a valid MeleeAttackPlan,
## mounts a translucent SkillBlade overlaid on the selection and loops the
## same swing sim that resolve() runs. On commit, BattleSystem awaits
## launch() to play the swing live with damage application.

const _FADE: float = 0.4

@export var battle_system: BattleSystem

var _ghost: SkillBlade
# Generation token so in-flight playback coroutines self-cancel when the
# selection changes underneath them. Bump on every spawn/teardown.
var _gen: int = 0

# #170 live-swing pop state, valid only during a launch()ed swing. `_dead_at`
# gates which hits actually land; `_pending_pops` (particle_idx -> Pop) fires the
# pop VFX/signal once, at the killing contact. Reset each launch(). #502:
# sourced from MeleeAttackPlan.last_live_gate.result — the applier's ACCEPTED
# set, read back after BattleSystem already applied it live — never a rescan.
var _dead_at: Dictionary = {}
var _pending_pops: Dictionary = {}
var _attacker: Entity
# FIFO of the DamageInstances resolve() actually applied (#474), consumed as
# each live hit passes the same edge/pop filters skill_blade.gd/resolve() both
# apply — see MeleeAttackPlan.last_hits.
var _pending_hits: Array[DamageInstance] = []


func _ready() -> void:
	if battle_system != null:
		battle_system.attack_plan_changed.connect(_on_plan_changed)
		battle_system.attack_plan_state_changed.connect(_refresh)


func _on_plan_changed(_plan: AttackPlan) -> void:
	_refresh()


func _refresh() -> void:
	var plan := battle_system.attack_plan
	if plan is MeleeAttackPlan and plan.is_valid():
		_spawn_blade(plan as MeleeAttackPlan)
		_run_preview_loop(_gen)
	else:
		_teardown()


## Pure-animation replay of a swing BattleSystem already resolved and
## applied. Spawns a fresh live blade purely for visuals and plays back
## [member MeleeAttackPlan.last_trajectory] / [member
## MeleeAttackPlan.last_events] — the SAME scan [method
## MeleeAttackPlan.resolve] already ran and BattleSystem already applied
## synchronously. Does NOT rescan: a rescan taken here would run after the
## depletion cascade and re-derive damage from a fresh blade state, drifting
## from what [OutcomeApplier] actually landed (#474) — a bug about replaying
## a finished mutation. #502 moved the LANDING gate itself to consumption
## time; this replay reads its result back via [member
## MeleeAttackPlan.last_live_gate], which [BladeDamageInstance.land_on]
## already populated with what really happened, live, during
## BattleSystem's synchronous apply — the applier's accepted set, not a
## rescan and not the pre-swing estimate ([member MeleeAttackPlan.last_pops]).
func launch(plan: MeleeAttackPlan) -> void:
	_spawn_blade(plan)
	var blade := _ghost
	if blade == null:
		return
	var gen := _gen
	var traj := plan.last_trajectory
	var events := plan.last_events
	var gate := plan.last_live_gate
	var result := gate.result if gate != null else null
	_dead_at = result.dead_at if result != null else {}
	_pending_pops = {}
	_pending_hits = plan.last_hits.duplicate()
	if result != null:
		for pop in result.pops:
			_pending_pops[pop.particle_idx] = pop
	_attacker = plan.attacker
	blade.hit.connect(_on_live_hit)
	await blade.play(traj, events, false)
	if gen != _gen or blade != _ghost:
		return
	var fade := create_tween()
	fade.tween_property(blade, "modulate", Color(0.55, 0.55, 0.55, 0.0), 0.45)
	await fade.finished
	if blade == _ghost:
		_ghost = null
	blade.queue_free()


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


## Pure observer: damage was already applied synchronously by
## BattleSystem off the same events this swing is replaying (#474). This
## replay's own timeline (per-event [param t], already driving [method
## SkillBlade.play]'s animation) doubles as the presentation clock:
## [signal Events.damage_shown] fires here, at the same [param t] the live
## swing visually lands the hit — never gating the swing, never touching
## model state.
func _on_live_hit(
		hitter_idx: int,
		is_edge: bool,
		target: SkillNode,
		t: float,
		damage: float) -> void:
	if target == null:
		return
	# D-1 MVP: edges are inert (resolve() skips them too) — no reveal.
	if is_edge:
		return
	# #502: resolve() now builds one DamageInstance per non-edge event
	# (whether or not it actually lands — that's last_live_gate's call), so
	# every branch below pops the FIFO exactly once to stay 1:1 with it.
	var hit: DamageInstance = null
	if not _pending_hits.is_empty():
		hit = _pending_hits.pop_front()
	# A live-popped hitter vertex landed no damage (BladeDamageInstance.land_on
	# vetoed it) — no presentation reveal for a hit that was never landed,
	# only the pop cue, fired once at the killing contact.
	if _dead_at.has(hitter_idx) and t >= _dead_at[hitter_idx]:
		var pop = _pending_pops.get(hitter_idx)
		if pop != null:
			_pending_pops.erase(hitter_idx)
			Events.blade_vertex_popped.emit(pop.defender, _attacker, pop.position)
		return
	# skill_blade.gd's own replay blade re-derives `damage` from a freshly
	# rebuilt vertex_damage array (live stats, not what was actually applied),
	# so it's ignored here in favour of the real effective_amount
	# BattleSystem's take_damage stashed on the matching DamageInstance — 0.0
	# if the live gate vetoed it (e.g. #502's already-dead target: no dud,
	# indistinguishable from a miss).
	var effective: float = damage
	if hit != null:
		effective = hit.effective_amount
	Events.damage_shown.emit(target, effective)


func _teardown() -> void:
	_gen += 1
	if _ghost != null:
		_ghost.stop()
		_ghost.queue_free()
		_ghost = null
