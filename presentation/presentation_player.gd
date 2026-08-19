class_name PresentationPlayer
extends Node

## Owns the view store and is the single writer of view state (#488). Mounted
## in `scenes/game_root.tscn` as `%PresentationPlayer`; `RevealRecorder.player`
## is assigned during `GameRoot` composition.
##
## In this child (#489) the player only updates its own store — it does not
## yet push to `SkillNode`/`Entity` (`set_view_state` arrives in #491). Tests
## read the store through [method shown_hp] / [method shown_owner] /
## [method shown_health].

var _shown_hp: Dictionary = {}     # SkillNode -> float
var _shown_owner: Dictionary = {}  # SkillNode -> Entity
var _shown_health: Dictionary = {} # Entity -> float


## Walks [param timeline] on the wall clock, awaiting between each event's
## `t`. Seeds every subject's store entry with its first event's
## [member RevealEvent.from_value] at t=0 before advancing.
func play(timeline: RevealTimeline) -> void:
	if timeline.events.is_empty():
		return
	var seeded: Dictionary = {}
	for e in timeline.events:
		var key = _seed_key(e)
		if key != null and not seeded.has(key):
			seeded[key] = true
			_apply_seed(e)
	var elapsed := 0.0
	for e in timeline.events:
		var wait := e.t - elapsed
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		elapsed = e.t
		apply_now(e)


## Headless / muted path: applies every event's final state immediately, no
## waiting.
func play_instant(timeline: RevealTimeline) -> void:
	for e in timeline.events:
		apply_now(e)


## Pass-through path (#489 has no caller yet; #490/#491 wire the recorder).
## Applies one event's post-mutation state to the store immediately.
func apply_now(event: RevealEvent) -> void:
	match event.kind:
		RevealEvent.Kind.NODE_HP:
			if is_instance_valid(event.node):
				_shown_hp[event.node] = event.to_value
		RevealEvent.Kind.NODE_DEATH:
			pass
		RevealEvent.Kind.NODE_OWNER_LOST:
			if is_instance_valid(event.node):
				_shown_owner[event.node] = null
		RevealEvent.Kind.ENTITY_HEALTH:
			if is_instance_valid(event.entity):
				_shown_health[event.entity] = event.to_value
		RevealEvent.Kind.ENTITY_WOUND:
			pass
		RevealEvent.Kind.ENTITY_DEATH:
			pass


func shown_hp(node: SkillNode) -> float:
	if not is_instance_valid(node):
		return 0.0
	if _shown_hp.has(node):
		return _shown_hp[node]
	return node.get_current_hp()


func shown_owner(node: SkillNode) -> Entity:
	if not is_instance_valid(node):
		return null
	if _shown_owner.has(node):
		var stored = _shown_owner[node]
		return stored if is_instance_valid(stored) else null
	return node.owned_by


func shown_health(entity: Entity) -> float:
	if not is_instance_valid(entity):
		return 0.0
	if _shown_health.has(entity):
		return _shown_health[entity]
	if entity.stat_board != null and entity.stat_board.health != null:
		return entity.stat_board.health.current
	return 0.0


## Returns the store key an event seeds at t=0, or null for kinds with no
## dedicated store (NODE_DEATH, ENTITY_WOUND, ENTITY_DEATH).
func _seed_key(event: RevealEvent):
	match event.kind:
		RevealEvent.Kind.NODE_HP, RevealEvent.Kind.NODE_OWNER_LOST:
			return event.node
		RevealEvent.Kind.ENTITY_HEALTH:
			return event.entity
		_:
			return null


func _apply_seed(event: RevealEvent) -> void:
	match event.kind:
		RevealEvent.Kind.NODE_HP:
			if is_instance_valid(event.node):
				_shown_hp[event.node] = event.from_value
		RevealEvent.Kind.NODE_OWNER_LOST:
			if is_instance_valid(event.node):
				_shown_owner[event.node] = event.entity
		RevealEvent.Kind.ENTITY_HEALTH:
			if is_instance_valid(event.entity):
				_shown_health[event.entity] = event.from_value
