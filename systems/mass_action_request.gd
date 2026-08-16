class_name MassActionRequest
extends RefCounted

## A pending multi-node allocate-path or deallocate-cascade confirmation
## (see docs/domain/... mass-action confirm panel). Built by
## PlayerInputController when a distant/would-island click can't resolve as a
## single-node action, handed to MassActionConfirmPanel via
## PlayerInputController.mass_action_pending_changed. Unlike LootPickRequest
## there's no resolve()/handled/auto-resolve handshake — this only ever
## originates from a direct player click, never something an NPC or headless
## test needs to auto-resolve.

enum Verb { ALLOCATE, DEALLOCATE }

var entity: Entity
var verb: Verb
## ALLOCATE: the full path, frontier anchor (already owned) at [0]. Only
## [code]nodes[1..][/code] are new allocations.
## DEALLOCATE: the full cascade set (target + everything it would island),
## in no particular order — deallocate_set doesn't care.
var nodes: Array[SkillNode] = []
## ALLOCATE only: nodes[1 .. affordable_count] is the SP-affordable prefix;
## the remainder (if any) is shown but not executed on confirm.
var affordable_count: int = 0
## ALLOCATE only: the originally-clicked node, for "reaches target?" display.
var target: SkillNode = null


func _init(entity_: Entity, verb_: Verb, nodes_: Array[SkillNode]) -> void:
	entity = entity_
	verb = verb_
	nodes = nodes_
