class_name AllocationSystem
extends Node

## The home for the allocate/deallocate action. SkillNode and Entity stay
## mutually agnostic — they only carry their own data; this system reads
## from the node, writes to both sides, emits the event.
##
## Where validation, costs, addons, and level-up gating will hook in as
## those systems land.

signal allocated(node: SkillNode, entity: Entity)
signal deallocated(node: SkillNode, previous_owner: Entity)


func can_allocate(node: SkillNode, entity: Entity) -> bool:
	if entity == null or node == null:
		return false
	if node.owned_by != null:
		return false
	# TODO: SP available on entity, neighbour-adjacency in entity's territory,
	# addons that gate allocation. None of that exists yet.
	return true


func allocate(node: SkillNode, entity: Entity) -> bool:
	if not can_allocate(node, entity):
		return false
	node.owned_by = entity
	# TODO: push node.modifiers onto entity.stat_board once the board has
	# an add_modifier API. Until then, allocation is just ownership.
	allocated.emit(node, entity)
	return true


func deallocate(node: SkillNode) -> bool:
	var previous := node.owned_by
	if previous == null:
		return false
	node.owned_by = null
	# TODO: remove node.modifiers from previous.stat_board (same gating).
	deallocated.emit(node, previous)
	return true
