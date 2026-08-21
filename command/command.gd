class_name Command
extends Resource

## One serializable world mutation — the vocabulary every peer applies through
## (#509, `docs/domain/multiplayer-sync-model.md`).
##
## A command is DATA, never a call. It carries wire identifiers only:
## [member Entity.entity_id] for the actor, [member SkillNode.stable_id] for
## any node it touches. **Never a `SkillNode` or `Entity` reference** — see
## `.claude/rules/multiplayer-sync.md`. Resolving those ids back to live
## objects is the applier's job (#510), not the command's.
##
## Serialization is a plain [Dictionary] of primitives, so it survives any
## transport Godot can encode. Each concrete type declares a `TAG` and its own
## `static from_dict`; [CommandCodec] owns the tag -> type dispatch, and is a
## separate class deliberately — a base that named its own subclasses would be
## a parse-time cycle.
##
## Fields are plain vars, never `@export` — a command is a message, not
## authored content, and its serialized form is [method to_dict] rather than a
## `.tres`.
##
## Nothing here validates. A command says what was asked for; whether it is
## legal is decided at apply time, by the same gated system that decides it
## offline today.

## The actor. 0 is unminted — legal on the wire only in the sense that the
## applier will fail to resolve it.
var entity_id: int = 0


func _init(entity_id_: int = 0) -> void:
	entity_id = entity_id_


## Wire tag for this concrete type. Every subclass overrides it with its own
## `TAG` const; the base's empty tag never round-trips, by design.
func type_tag() -> StringName:
	return &""


## The wire form. Subclasses call `super()` and add their own fields, so
## every dictionary carries `type` + `entity_id` at minimum.
func to_dict() -> Dictionary:
	return {"type": type_tag(), "entity_id": entity_id}
