class_name PresentationPlayer
extends Node

## Owns the view store and is the single writer of view state (#488/#491).
## Mounted in `scenes/game_root.tscn` as `%PresentationPlayer`;
## `RevealRecorder.player` is assigned during `GameRoot` composition.
##
## Every applied event is PUSHED into the subject's own dumb view fields
## ([method SkillNode.set_view_state] / [method Entity.set_view_health]) —
## the node/entity is the thing readers should bind to; [method shown_hp] /
## [method shown_owner] / [method shown_health] stay as this class's own
## bookkeeping (and the tie-break for `from_value` seeding) rather than the
## primary read path. [signal event_revealed] is the generic hook for
## consumers that react to a REVEAL as an event (a shatter, a territory
## refresh) rather than to a continuous value (AllocationVFX, AuraOverlay).

var _shown_hp: Dictionary = {}     # SkillNode -> float
var _shown_owner: Dictionary = {}  # SkillNode -> Entity
var _shown_health: Dictionary = {} # Entity -> float

## Fired for every event this player applies — pass-through, `play_instant`,
## or one wall-clock step of `play`. Kind-agnostic; consumers filter by
## [member RevealEvent.kind].
signal event_revealed(event: RevealEvent)


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


## Applies one event's post-mutation state — pushed into the store AND the
## subject's own view fields — then fires [signal event_revealed]. This is
## both the pass-through path (`RevealRecorder._record` when nothing is
## recording) and the per-step application `play`/`play_instant` walk into.
func apply_now(event: RevealEvent) -> void:
	match event.kind:
		RevealEvent.Kind.NODE_HP:
			if is_instance_valid(event.node):
				_shown_hp[event.node] = event.to_value
				_push_node(event.node)
		RevealEvent.Kind.NODE_DEATH:
			pass
		RevealEvent.Kind.NODE_OWNER_LOST:
			if is_instance_valid(event.node):
				_shown_owner[event.node] = null
				_push_node(event.node)
		RevealEvent.Kind.ENTITY_HEALTH:
			if is_instance_valid(event.entity):
				_shown_health[event.entity] = event.to_value
				event.entity.set_view_health(event.to_value)
		RevealEvent.Kind.ENTITY_WOUND:
			if is_instance_valid(event.entity):
				Events.entity_wounded.emit(event.entity, int(event.to_value))
		RevealEvent.Kind.ENTITY_DEATH:
			if is_instance_valid(event.entity):
				Events.entity_death_shown.emit(event.entity)
	event_revealed.emit(event)


func _push_node(node: SkillNode) -> void:
	node.set_view_state(shown_hp(node), shown_owner(node))


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
				_push_node(event.node)
		RevealEvent.Kind.NODE_OWNER_LOST:
			if is_instance_valid(event.node):
				_shown_owner[event.node] = event.entity
				_push_node(event.node)
		RevealEvent.Kind.ENTITY_HEALTH:
			if is_instance_valid(event.entity):
				_shown_health[event.entity] = event.from_value
				event.entity.set_view_health(event.from_value)
