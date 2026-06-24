@tool
class_name MagicBounceCoordinator
extends VFXCoordinator

## Plays a multi-hop spell's visual sequence. Groups [member AttackOutcome.hits]
## by [member CastSpell.hop_index] (read off [member DamageInstance.source])
## and fires one wave per hop on a fixed clock: hop N spawns at
## [code]t = N * per_hop_duration[/code] relative to [method play].
##
## ## The clock is the ground truth
##
## Animations do NOT gate the clock. Each spawned [Projectile] is given
## [member per_hop_duration] as its flight budget so the visual lands
## roughly when the next wave fires — but if a visual lingers past its
## window (long trail, slow fade) it keeps playing in parallel with the
## next hop's projectiles. That parallel-stacking IS the look for branchy
## spells (fork lightning). Awaiting "previous projectile finished" would
## let a slow fork hold up the propagation; we don't do that.

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/glowing_dot.tscn")

## Fired immediately before each hop wave's projectiles are spawned.
## Tests assert the emission cadence here; gameplay can use it for SFX cues.
signal wave_started(hop_index: int, hits_in_wave: int)

@export var projectile_path: ProjectilePath
@export var visual_scene: PackedScene = _DEFAULT_VISUAL
## Seconds between hop waves. Sets the cadence of the BFS clock.
@export var per_hop_duration: float = 0.4
## Per-projectile flight duration. Should be ≤ [member per_hop_duration]
## so the ball lands before the next wave fires; set slightly shorter for
## a small "landed, then next hop" beat.
@export var flight_time: float = 0.35
@export var face_velocity: bool = true


# `pending` is Array[int] so closures can mutate it (lambdas capture locals
# by value). Tracks projectiles still in-flight so we don't queue_free this
# coordinator before its children drain.
func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	if outcome == null or outcome.hits.is_empty():
		return
	var waves := _group_by_hop(outcome.hits)
	var hop_indices: Array = waves.keys()
	hop_indices.sort()
	var pending: Array[int] = [0]
	for i in hop_indices.size():
		var hop := int(hop_indices[i])
		var wave: Array = waves[hop]
		wave_started.emit(hop, wave.size())
		for hit_v in wave:
			var hit: DamageInstance = hit_v
			_spawn_projectile(hit, pending)
		if i < hop_indices.size() - 1:
			await get_tree().create_timer(per_hop_duration).timeout
	while pending[0] > 0:
		await get_tree().process_frame


# Groups hits by `hit.source.hop_index` (the CastSpell carries it). Hits
# whose source isn't a CastSpell (defensive — shouldn't happen for spells)
# bucket into hop 0 so they still play in the first wave.
func _group_by_hop(hits: Array[DamageInstance]) -> Dictionary:
	var waves: Dictionary = {}
	for hit in hits:
		var hop := 0
		var src: Variant = hit.source
		if src is CastSpell:
			hop = (src as CastSpell).hop_index
		if not waves.has(hop):
			waves[hop] = []
		waves[hop].append(hit)
	return waves


func _spawn_projectile(hit: DamageInstance, pending: Array[int]) -> void:
	if hit.origin == null or hit.target == null:
		return
	var proj := Projectile.new()
	proj.path = _resolved_path()
	proj.visual_scene = visual_scene
	proj.flight_time = flight_time
	proj.face_velocity = face_velocity
	add_child(proj)
	pending[0] += 1
	proj.arrived.connect(func() -> void:
		if hit.target != null:
			hit.target.take_damage(hit.amount, hit))
	proj.tree_exiting.connect(func() -> void:
		pending[0] -= 1)
	proj.launch(hit.origin.global_position, hit.target.global_position, 0.0)


func _resolved_path() -> ProjectilePath:
	if projectile_path != null:
		return projectile_path
	return BezierArcPath.new()
