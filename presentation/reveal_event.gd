class_name RevealEvent
extends RefCounted

## [b]PARKED — nothing references this class (#504). See
## presentation/README.md before touching or deleting it.[/b] Design A of the
## presentation clock; the game runs design B.

## One recorded change to a subject's presented state, produced by
## [RevealRecorder] and consumed by [PresentationPlayer]. See #488 for the
## full design; this is the payload shape.

enum Kind {
	NODE_HP,            ## node combat HP changed
	NODE_DEATH,         ## node combat HP reached 0
	NODE_OWNER_LOST,    ## node was force-deallocated
	ENTITY_HEALTH,      ## entity health pool changed
	ENTITY_WOUND,       ## entity gained wounded SP
	ENTITY_DEATH,       ## entity died
}

var kind: Kind
## Seconds from launch — the reveal clock. Set by [RevealRecorder]'s cause
## stack, not by the caller.
var t: float = 0.0
## Subject for NODE_* kinds.
var node: SkillNode = null
## Subject for ENTITY_* kinds; owner for NODE_OWNER_LOST.
var entity: Entity = null
## The value BEFORE the mutation. Carried on the event rather than snapshotted
## by the player at play time: by the time the player runs, the model is
## already fully mutated (#474), so there is nothing left to snapshot at play
## time. Do not "simplify" this into a play-time snapshot — that reintroduces
## the seeding bug #488 fixes.
var from_value: float = 0.0
## The value AFTER the mutation.
var to_value: float = 0.0


static func node_hp(node: SkillNode, from: float, to: float) -> RevealEvent:
	var e := RevealEvent.new()
	e.kind = Kind.NODE_HP
	e.node = node
	e.from_value = from
	e.to_value = to
	return e


static func node_death(node: SkillNode) -> RevealEvent:
	var e := RevealEvent.new()
	e.kind = Kind.NODE_DEATH
	e.node = node
	return e


static func node_owner_lost(node: SkillNode, previous_owner: Entity) -> RevealEvent:
	var e := RevealEvent.new()
	e.kind = Kind.NODE_OWNER_LOST
	e.node = node
	e.entity = previous_owner
	return e


static func entity_health(entity: Entity, from: float, to: float) -> RevealEvent:
	var e := RevealEvent.new()
	e.kind = Kind.ENTITY_HEALTH
	e.entity = entity
	e.from_value = from
	e.to_value = to
	return e


static func entity_wound(entity: Entity, amount: float) -> RevealEvent:
	var e := RevealEvent.new()
	e.kind = Kind.ENTITY_WOUND
	e.entity = entity
	e.to_value = amount
	return e


static func entity_death(entity: Entity) -> RevealEvent:
	var e := RevealEvent.new()
	e.kind = Kind.ENTITY_DEATH
	e.entity = entity
	return e
