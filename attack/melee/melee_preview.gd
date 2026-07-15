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
# pop VFX/signal once, at the killing contact. Reset each launch().
var _dead_at: Dictionary = {}
var _pending_pops: Dictionary = {}
var _attacker: Entity


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


## Commit playback. Spawn a fresh live blade, run sim + scan, play with
## damage application during the swing, fade out, free. Awaitable.
func launch(plan: MeleeAttackPlan) -> void:
	_spawn_blade(plan)
	var blade := _ghost
	if blade == null:
		return
	var gen := _gen
	var traj := blade.simulate(MeleeAttackPlan.SWING_DURATION)
	var space_state := blade.get_world_2d().direct_space_state
	var exclude := plan.collect_target_excludes()
	var events := BladeHitScan.scan(
			traj, blade.state, space_state, 0xFFFFFFFF, exclude)
	# #170: resolve defensive spike pops once, off the same scan resolve() uses.
	var pops := BladePopResolver.resolve(events, blade.state, plan.attacker)
	_dead_at = pops.dead_at
	_pending_pops = {}
	for pop in pops.pops:
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


func _on_live_hit(
		hitter_idx: int,
		_is_edge: bool,
		target: SkillNode,
		t: float,
		damage: float) -> void:
	if target == null:
		return
	# #170: a popped/disintegrated vertex deals no more damage. The first such
	# event for a killed vertex is its killing contact — pop the spike there.
	if _dead_at.has(hitter_idx) and t >= _dead_at[hitter_idx]:
		var pop = _pending_pops.get(hitter_idx)
		if pop != null:
			_pending_pops.erase(hitter_idx)
			Events.blade_vertex_popped.emit(pop.defender, _attacker, pop.position)
		return
	var di := DamageInstance.new()
	di.amount = damage
	di.type = DamageInstance.Type.PHYSICAL
	di.target = target
	target.take_damage(damage, di)


func _teardown() -> void:
	_gen += 1
	if _ghost != null:
		_ghost.stop()
		_ghost.queue_free()
		_ghost = null
