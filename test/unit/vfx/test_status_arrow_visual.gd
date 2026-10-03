extends GutTest

## The status arrow (#1351): a typed shot flies its [AmmoType]'s own visual —
## picked per shot by [ArrowVolleyCoordinator] off the hit's `ammo_type_id`, so
## a replayed record draws the same arrows — and the visual's tip and trail
## speak the type's status colour ([member StatusDef.tint], hue asserted, never
## the tier float). It reports `finished` only once its trail has drained.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON: AmmoType = preload("res://attack/ammo/types/poison.tres")
const _STATUS_ARROW := "res://ui/vfx/projectile/visual/status_arrow.tscn"
const _POISON_ARROW := "res://ui/vfx/projectile/visual/arrows/poison_arrow.tscn"
const _LIGHT_ARROW := "res://ui/vfx/projectile/visual/light_arrow.tscn"

var _graph: Graph
var _origin: SkillNode
var _target: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_origin = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_target = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_origin.position = Vector2(0, 0)
	_target.position = Vector2(500, 0)
	_graph.add_skill_node(_origin)
	_graph.add_skill_node(_target)


func _hit(ammo_type_id: StringName, key: float) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.origin = _origin
	hit.target = _target
	hit.amount = 5.0
	hit.effective_amount = 5.0
	hit.structural_key = key
	hit.ammo_type_id = ammo_type_id
	return hit


func _outcome() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_hit(&"poison", 0.02))
	outcome.hits.append(_hit(AmmoTypeRoster.BASE_ID, 0.04))
	return outcome


## The scene each launched projectile was handed, in hit order; the
## projectiles are then freed so the un-awaited play drains at once.
func _spawned_scenes(outcome: AttackOutcome) -> Array[String]:
	var coord := ArrowVolleyCoordinator.new()
	coord.flight_time = 0.02
	add_child_autofree(coord)
	coord.play(outcome)
	var out: Array[String] = []
	for child in coord.get_children():
		if child is Projectile:
			var scene: PackedScene = (child as Projectile).visual_scene
			out.append(scene.resource_path if scene != null else "")
			child.queue_free()
	await wait_physics_frames(2)
	return out


func test_a_poison_shot_flies_the_status_arrow_and_a_base_shot_the_light_arrow() -> void:
	var scenes := await _spawned_scenes(_outcome())
	assert_eq(scenes, [_POISON_ARROW, _LIGHT_ARROW] as Array[String],
			"each shot's visual is its ammo type's scene; the base keeps the default")


func test_a_rebuilt_record_picks_the_same_scenes() -> void:
	var wire: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(_outcome(), _graph)))
	var rebuilt := AttackRecord.rebuild(wire, _graph)
	var scenes := await _spawned_scenes(rebuilt)
	assert_eq(scenes, [_POISON_ARROW, _LIGHT_ARROW] as Array[String],
			"a peer replaying the record draws the arrows the host drew")


func _status_arrow() -> StatusArrow:
	var arrow: StatusArrow = (load(_STATUS_ARROW) as PackedScene).instantiate()
	add_child_autofree(arrow)
	arrow.status_tint = _POISON.first_status_def().tint
	return arrow


func test_tip_and_trail_carry_the_status_hue() -> void:
	var arrow := _status_arrow()
	var hue: float = _POISON.first_status_def().tint.h
	var tip: Polygon2D = arrow.get_node(^"%Tip")
	var trail: GPUParticles2D = arrow.get_node(^"%Trail")
	assert_true(tip.visible, "a status arrow shows its tip")
	assert_almost_eq(tip.color.h, hue, 0.02, "the tip is the status colour")
	assert_almost_eq(trail.modulate.h, hue, 0.02, "the trail is the status colour")
	assert_true(trail.modulate.s > 0.3, "the trail is coloured, not white")


func test_finished_waits_for_the_trail_to_drain() -> void:
	var arrow := _status_arrow()
	var trail: GPUParticles2D = arrow.get_node(^"%Trail")
	var burst: GPUParticles2D = arrow.get_node(^"%Burst")
	arrow.hold_seconds = 0.0
	arrow.fade_seconds = 0.0
	watch_signals(arrow)
	arrow._on_launch()
	assert_true(trail.emitting, "the trail streams while the arrow flies")
	arrow._on_arrival()
	assert_false(trail.emitting, "the trail stops emitting at the impact")
	assert_almost_eq(arrow.drain_seconds(), maxf(trail.lifetime, burst.lifetime), 0.0001,
			"the drain is the longest-lived emitter's lifetime")
	assert_signal_not_emitted(arrow, "finished", "not finished while the trail drains")


## The impact beats land just after arrival; on either the status burst is
## withdrawn — a dud never landed, an absorbed shot is the defender's verdict.
func test_a_dud_or_absorbed_arrow_shows_no_status_burst() -> void:
	for beat in [&"dud", &"absorbed"]:
		var arrow := _status_arrow()
		var burst: GPUParticles2D = arrow.get_node(^"%Burst")
		arrow._on_launch()
		arrow._on_arrival()
		assert_true(burst.visible and burst.emitting, "precondition: a landing arrow bursts")
		if beat == &"dud":
			arrow._on_dud()
		else:
			arrow._on_absorbed(false)
		assert_false(burst.visible or burst.emitting, "no status burst on a %s" % beat)
