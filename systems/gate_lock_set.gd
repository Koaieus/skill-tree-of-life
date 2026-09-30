class_name GateLockSet
extends RefCounted

## The gates each entity has locked — a seat-local input filter, never world
## state and never synced. A locked gate is left out of every bulk gate action;
## a deliberate span click still flips it.
##
## Keyed by the entity's `Object.get_instance_id()` (never `entity_id`, which is
## 0 until the entity enters its container, and never the Entity, which compares
## equal to null once freed) so a hot-seat handover keeps each player's locks.
## A gate is named by its sorted stable-id pair — see [method key_of] — so a
## lock survives the Gate node being rebuilt.

var _locks: Dictionary[int, Dictionary] = {}


## The direction-free name of [param gate] on [param graph].
static func key_of(graph: Graph, gate: Gate) -> Vector2i:
	var a := graph.get_stable_id(gate.from)
	var b := graph.get_stable_id(gate.to)
	return Vector2i(mini(a, b), maxi(a, b))


func is_locked(entity: Entity, key: Vector2i) -> bool:
	if entity == null:
		return false
	var set_: Dictionary = _locks.get(entity.get_instance_id(), {})
	return set_.has(key)


func set_locked(entity: Entity, key: Vector2i, locked: bool) -> void:
	if entity == null:
		return
	var id := entity.get_instance_id()
	if not _locks.has(id):
		_locks[id] = {}
	if locked:
		_locks[id][key] = true
	else:
		_locks[id].erase(key)


## Does [param entity] hold any lock at all?
func any_locked(entity: Entity) -> bool:
	return entity != null and not (_locks.get(entity.get_instance_id(), {}) as Dictionary).is_empty()
