class_name AllocationSystem
extends Node

## Allocation rules (MVP):
## - Target node must be unallocated.
## - Allocating entity must have ≥ 1 SP (if it tracks SP via a stat_board).
## - Target must be adjacent to a node already owned by the entity, UNLESS
##   the entity has nothing owned yet — the first allocation is free of
##   adjacency for core placement.
## - allocate: SP -= 1 via skill_points.spend(1); node.modifiers pushed onto
##   entity.stat_board.add_modifier().
## - deallocate (voluntary): blocked if it would island any of the entity's
##   other owned nodes from its core (via entity.navigator); on success:
##   modifiers removed, deallocation_points -= 1, SP refunded.
##
## Forced-deallocation by attack lives elsewhere — it calls deallocate() then
## skill_points.wound(1) to reclassify the refund as a wound. Buffer-tap temp
## SP / temp allocations live on TurnManager (tag at allocate time; phase end
## sweep deallocates and drains temp from current).
##
## `graph` is optional. Without it (e.g. an isolated test), adjacency is
## skipped — entities can allocate any unallocated node. SP gating still
## runs. Islanding is gated by `entity.navigator` and is skipped when the
## entity has no navigator (e.g. an entity instantiated without a graph
## ancestor).

signal allocated(node: SkillNode, entity: Entity)
signal deallocated(node: SkillNode, previous_owner: Entity)

@export var graph: Graph
@export var navigator: Navigator


func can_allocate(node: SkillNode, entity: Entity) -> bool:
	if entity == null or node == null:
		return false
	if node.owned_by != null:
		return false
	var board := entity.stat_board
	if board != null and board.skill_points != null and board.skill_points.current < 1:
		return false
	if _has_any_owned_node(entity) and not _is_adjacent_to_owned(node, entity):
		return false
	return true

func can_deallocate(node: SkillNode, entity: Entity) -> bool:
	if entity == null or node == null:
		return false
	if node.owned_by != entity:
		return false
	var board := entity.stat_board
	if board != null and board.deallocation_points != null and board.deallocation_points.current < 1:
		return false
	if entity.navigator != null and entity.navigator.is_cut_disconnecting_core(node):
		return false
	return true


func allocate(node: SkillNode, entity: Entity) -> bool:
	if not can_allocate(node, entity):
		return false
	var board := entity.stat_board
	if board != null and board.skill_points != null:
		board.skill_points.spend(1)
	node.owned_by = entity
	if entity.navigator != null:
		entity.navigator.mirror_add(node)
	if board != null:
		for m in node.modifiers:
			board.add_modifier(m)
	allocated.emit(node, entity)
	return true


func deallocate(node: SkillNode, entity: Entity) -> bool:
	if not can_deallocate(node, entity):
		return false
	var previous := node.owned_by
	if previous == null:
		return false
	var board := previous.stat_board
	if board != null:
		for m in node.modifiers:
			board.remove_modifier(m)
	if previous.navigator != null:
		previous.navigator.mirror_remove(node)
	node.owned_by = null

	if board != null:
		if board.deallocation_points != null:
			board.deallocation_points.deplete(1)
		if board.skill_points != null:
			board.skill_points.refund(1)
	deallocated.emit(node, previous)
	return true


func _has_any_owned_node(entity: Entity) -> bool:
	if graph == null:
		return false
	for n in graph.get_skill_nodes():
		if n.owned_by == entity:
			return true
	return false


func _is_adjacent_to_owned(node: SkillNode, entity: Entity) -> bool:
	if graph == null:
		return false
	for e in graph.get_edges():
		var other: SkillNode = null
		if e.from == node:
			other = e.to
		elif e.to == node:
			other = e.from
		else:
			continue
		if other != null and other.owned_by == entity:
			return true
	return false
