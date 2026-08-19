class_name RevealRecorder
extends RefCounted

## Ambient recorder (#488): a static context opened around a mutation, with a
## cause stack that stamps `t` onto everything it hears. Deliberately not a
## parameter threaded through five systems — record sites are one line each,
## with no timeline argument to plumb.
##
## Pass-through mode: when no timeline is open ([member is_recording] false —
## upkeep, an effect, a sandbox panel, a test calling a mutator directly), a
## record call applies straight to [member player] via
## [method PresentationPlayer.apply_now] instead of queueing. That is the only
## fallback anywhere in the presentation system.
##
## #489 wires no call sites — #490 adds the six record calls and three cause
## scopes listed in #488.

static var _timeline: RevealTimeline = null
## Each entry: {"base": float, "stride": float, "count": int}. `stride` is 0.0
## for a plain [method push_cause] scope (every record in it shares one `t`)
## and [constant RevealTimeline.CASCADE_STEP] for a [method push_strip_scope]
## (each record in it takes the next stagger slot).
static var _cause_stack: Array[Dictionary] = []
## Assigned by `GameRoot` during composition; cleared on level exit. Static
## state outlives a scene change, so a stale reference here would dangle
## across a level reload if `GameRoot` didn't null it.
static var player: PresentationPlayer = null

static var is_recording: bool:
	get: return _timeline != null


static func begin(timeline: RevealTimeline) -> void:
	_timeline = timeline
	_cause_stack.clear()


static func end() -> RevealTimeline:
	var finished := _timeline
	if finished != null:
		finished.finalize()
	_timeline = null
	_cause_stack.clear()
	return finished


static func push_cause(base_t: float) -> void:
	_cause_stack.append({"base": base_t, "stride": 0.0, "count": 0})


static func pop_cause() -> void:
	_cause_stack.pop_back()


## Auto-staggers each record made inside the scope by
## [constant RevealTimeline.CASCADE_STEP], starting from whatever `t` is
## current when the scope opens — so a death strip fired from inside an
## already-open cause scope inherits that scope's base `t` with no extra
## attribution logic.
static func push_strip_scope() -> void:
	_cause_stack.append({"base": _current_t(), "stride": RevealTimeline.CASCADE_STEP, "count": 0})


static func pop_strip_scope() -> void:
	_cause_stack.pop_back()


static func node_hp(node: SkillNode, from: float, to: float) -> void:
	_record(RevealEvent.node_hp(node, from, to))


static func node_death(node: SkillNode) -> void:
	_record(RevealEvent.node_death(node))


static func node_owner_lost(node: SkillNode, previous_owner: Entity) -> void:
	_record(RevealEvent.node_owner_lost(node, previous_owner))


static func entity_health(entity: Entity, from: float, to: float) -> void:
	_record(RevealEvent.entity_health(entity, from, to))


static func entity_wound(entity: Entity, amount: float) -> void:
	_record(RevealEvent.entity_wound(entity, amount))


static func entity_death(entity: Entity) -> void:
	_record(RevealEvent.entity_death(entity))


static func _current_t() -> float:
	if _cause_stack.is_empty():
		return 0.0
	return _cause_stack.back()["base"]


static func _next_t() -> float:
	if _cause_stack.is_empty():
		return 0.0
	var scope: Dictionary = _cause_stack.back()
	var t: float = scope["base"] + scope["count"] * scope["stride"]
	scope["count"] += 1
	return t


static func _record(event: RevealEvent) -> void:
	event.t = _next_t()
	if _timeline != null:
		_timeline.append(event)
	elif player != null:
		player.apply_now(event)
