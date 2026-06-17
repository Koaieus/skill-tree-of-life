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
	var targets := plan.collect_targets()
	var events := BladeHitScan.scan(traj, blade.state, targets)
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
		blade.build_from_skill_nodes(
				selection, plan.source, plan.get_induced_edges(), plan.attacker)
		blade.modulate.a = 0.35


func _on_live_hit(
		_hitter_idx: int,
		_is_edge: bool,
		target: SkillNode,
		_t: float,
		damage: float) -> void:
	if target == null:
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
