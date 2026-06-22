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
## Voluntary deallocation only — emitted from `deallocate()`. Forced kills
## emit `force_deallocated` instead, so cosmetic effects can distinguish a
## graceful lift-away from a shatter without sniffing context.
signal deallocated(node: SkillNode, previous_owner: Entity)
## Forced deallocation (attack-driven). Emitted by every `force_deallocate()`
## call — including each follow-up in a battle cascade. See
## `docs/domain/allocation-vfx.md`.
signal force_deallocated(node: SkillNode, previous_owner: Entity)

@export var graph: Graph
@export var navigator: Navigator
@export var turn_manager: TurnManager


## Register scene-authored ownership with the SP accounting. Called by
## GameRoot before _setup_level — walks the graph and calls claim(1) for
## every already-owned node, so a hand-authored dev_sandbox player ends up
## with the same `used` bookkeeping a procgen-spawned player gets via
## force_allocate. Procgen content arrives later (during _setup_level) and
## goes through force_allocate, which calls claim() itself — no double-count.
func register_scene_authored_ownership() -> void:
	if graph == null:
		return
	for n in graph.get_skill_nodes():
		if n.owned_by == null or n.owned_by.stat_board == null:
			continue
		if n.owned_by.stat_board.skill_points != null:
			n.owned_by.stat_board.skill_points.claim(1)


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
	if node.is_core():
		return false
	var board := entity.stat_board
	if board != null and board.deallocation_points != null and board.deallocation_points.current < 1:
		return false
	if entity.navigator != null and entity.navigator.would_disconnect_from(node, entity.core_location):
		return false
	return true


func allocate(node: SkillNode, entity: Entity) -> bool:
	if not can_allocate(node, entity):
		return false
	# spend(1) does current -= 1, used += 1. force_allocate would also call
	# claim(1) — that'd double-bump used and mint an extra SP. So inline the
	# rest of force_allocate's side-effects here, skipping the claim.
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


## Gating-free primitive: set ownership, mirror to navigator, push node
## modifiers onto entity's stat board, claim 1 SP into the entity's `used`
## bucket. allocate() composes this with SP gating + adjacency rules;
## procgen / scripted setup uses it directly.
##
## The claim(1) call is what mints the SP that backs the free allocation —
## without it, deallocating later would overflow the pool's max and silently
## lose the SP to clamping. See docs/domain/allocation_system.md.
func force_allocate(entity: Entity, node: SkillNode) -> void:
	if entity == null or node == null:
		return
	node.owned_by = entity
	if entity.navigator != null:
		entity.navigator.mirror_add(node)
	var board := entity.stat_board
	if board != null:
		if board.skill_points != null:
			board.skill_points.claim(1)
		for m in node.modifiers:
			board.add_modifier(m)
	allocated.emit(node, entity)


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


## Bypass for forced deallocation by attack. Skips can_deallocate guards
## (DP cost, would_disconnect, is_core check) and does not refund SP — the
## caller is responsible for the wound + core-HP-loss routing instead. This
## is the "elsewhere" referenced at the top of this file.
##
## Returns the previous owner so the caller can chain wound + health.deplete
## without re-reading owned_by (which is null after this call).
func force_deallocate(node: SkillNode) -> Entity:
	if node == null:
		return null
	var previous := node.owned_by
	if previous == null:
		return null
	var board := previous.stat_board
	if board != null:
		for m in node.modifiers:
			board.remove_modifier(m)
	if previous.navigator != null:
		previous.navigator.mirror_remove(node)
	node.owned_by = null
	force_deallocated.emit(node, previous)
	return previous


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
