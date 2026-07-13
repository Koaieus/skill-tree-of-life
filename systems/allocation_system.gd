@tool
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
## skill_points.wound(1) to reclassify the refund as a wound.
##
## `graph` is optional. Without it (e.g. an isolated test), adjacency is
## skipped — entities can allocate any unallocated node. SP gating still
## runs. Islanding is gated by `entity.navigator` and is skipped when the
## entity has no navigator (e.g. an entity instantiated without a graph
## ancestor).

## `forced` distinguishes the voluntary `allocate()` path (gameplay — false)
## from the `force_allocate()` primitive (spawn / procgen / scene-authored
## setup — true). Cosmetic consumers that should only react to gameplay (the
## #71 modifier pulses + #70 floaters) gate on `not forced`, so a level's
## setup allocations don't fire a pulse/floater flurry. The alloc spike fires
## for both (nodes visibly "drop in" as the level builds).
signal allocated(node: SkillNode, entity: Entity, forced: bool)
## Voluntary deallocation only — emitted from `deallocate()`. Forced kills
## emit `force_deallocated` instead, so cosmetic effects can distinguish a
## graceful lift-away from a shatter without sniffing context.
signal deallocated(node: SkillNode, previous_owner: Entity)
## Forced deallocation (attack-driven). Emitted by every `force_deallocate()`
## call — including each follow-up in a battle cascade. See
## `docs/domain/allocation-vfx.md`.
signal force_deallocated(node: SkillNode, previous_owner: Entity)
## Core movement (#21). Emitted after `move_core` commits the new
## `core_location`. `from_node` is the previous core slot, `to_node` the new
## one. Slide-tween consumers (SkillNode's CoreMarker) subscribe here rather
## than to `core_location_changed` so they get the previous position too.
signal core_moved(entity: Entity, from_node: SkillNode, to_node: SkillNode)

@export var graph: Graph
@export var navigator: Navigator
@export var turn_manager: TurnManager


func _ready() -> void:
	Events.entity_died.connect(_on_entity_died)


## Death cleanup (#18): strip a dead entity of every node it owns. Runs
## SYNCHRONOUSLY even though death can fire mid-cascade — `health.deplete()`
## inside BattleSystem's forced-dealloc loop (or SkillNode.take_damage) crosses
## 0 → `depleted` → Entity.die() → this. That's safe: BattleSystem's loop guards
## each step with `if n.owned_by != defender: continue`, so nodes we deallocate
## here are simply skipped when control returns to it — the loop doesn't restart,
## there's no re-entry. Synchronous is deliberately chosen over deferring: a
## deferred `deallocate_all_owned(entity)` races GameRoot freeing the corpse, and
## a deferred call whose Object arg is freed is dropped, orphaning the nodes
## (owned_by a freed entity). See test_npc_death_via_bus_deallocates_before_free.
func _on_entity_died(entity: Entity) -> void:
	deallocate_all_owned(entity)


## Force-deallocate every node the entity owns, via the same `force_deallocate`
## primitive the battle cascade uses (so VFX shatter + `force_deallocated` fire
## per node). The core node goes last — this is the only path that ever
## force-deallocates a core. Public so concede / despawn flows can reuse it.
func deallocate_all_owned(entity: Entity) -> void:
	if entity == null or graph == null:
		return
	var core := entity.core_location
	for n in graph.get_skill_nodes():
		if n != core and n.owned_by == entity:
			force_deallocate(n)
	if core != null and core.owned_by == entity:
		force_deallocate(core)


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
		# This path bypasses force_allocate, so it must grant node-borne effects
		# itself — otherwise a hand-authored keystone node is silently inert.
		_grant_node_effects(n, n.owned_by)


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
	if board != null and board.deallocation_points != null and board.deallocation_points.available() < 1:
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
	node.apply_entity_modifiers_to(board)
	_grant_node_effects(node, entity)
	# After the mirror update: an aura recomputing off this hook must see the
	# new node in the owned subgraph, not the stale one.
	entity.dispatch(&"_on_node_allocated", [node, false])
	allocated.emit(node, entity, false)
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
	if board != null and board.skill_points != null:
		board.skill_points.claim(1)
	node.apply_entity_modifiers_to(board)
	_grant_node_effects(node, entity)
	entity.dispatch(&"_on_node_allocated", [node, true])
	allocated.emit(node, entity, true)


func deallocate(node: SkillNode, entity: Entity) -> bool:
	if not can_deallocate(node, entity):
		return false
	var previous := node.owned_by
	if previous == null:
		return false
	var board := previous.stat_board
	_revoke_node_effects(node, previous)
	node.remove_entity_modifiers_from(board)
	if previous.navigator != null:
		previous.navigator.mirror_remove(node)
	node.owned_by = null
	# After the mirror drops the node and ownership clears — an aura recomputing
	# here must not still see the node as its own.
	previous.dispatch(&"_on_node_deallocated", [node, false])

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
	_revoke_node_effects(node, previous)
	node.remove_entity_modifiers_from(board)
	if previous.navigator != null:
		previous.navigator.mirror_remove(node)
	node.owned_by = null
	previous.dispatch(&"_on_node_deallocated", [node, true])
	force_deallocated.emit(node, previous)
	return previous


## Core movement (#21). Validates `move_core` preconditions without committing.
## - target must be owned by the entity (you only hop across your own subgraph)
## - target must differ from the current core slot (self-loops are not landings)
## - target must be adjacent via a non-self-loop edge to the current core slot
## - entity must have ≥ 1 movement_points
## Turn-ownership gating lives in the caller (PlayerInputController), which
## also routes the click channels (allocate / deallocate / move-core).
func can_move_core(entity: Entity, target: SkillNode) -> bool:
	if entity == null or target == null:
		return false
	var source := entity.core_location
	if source == null or target == source:
		return false
	if target.owned_by != entity:
		return false
	if not _is_adjacent_via_real_edge(source, target):
		return false
	var board := entity.stat_board
	if board != null and board.movement_points != null and board.movement_points.available() < 1:
		return false
	return true


## Core movement (#21). Hops `entity.core_location` to an adjacent owned node,
## spends 1 movement_points, and emits `core_moved` (for slide-tween VFX) plus
## the existing `core_location_changed` (for the CoreMarker swap, vision
## recompute, etc.). No cut-vertex check: the owned subgraph is unchanged.
func move_core(entity: Entity, target: SkillNode) -> bool:
	if not can_move_core(entity, target):
		return false
	var from_node := entity.core_location
	var board := entity.stat_board
	if board != null and board.movement_points != null:
		board.movement_points.deplete(1)
	# The setter dispatches `_on_core_moved` — it's the one point that catches
	# every core placement, including the opening one. Don't dispatch again here.
	entity.core_location = target
	core_moved.emit(entity, from_node, target)
	return true


## Grant every [Effect] a node carries to its new owner (#4). Covers the node's
## [Keystone] — whose runtime wiring its own docstring has advertised as a
## follow-up since it was written — and any addon-borne effects.
func _grant_node_effects(node: SkillNode, entity: Entity) -> void:
	if node == null or entity == null:
		return
	for e in node.get_node_effects():
		entity.grant_effect(e, node)


## Symmetric strip. Keyed by source node, so a node losing ownership takes only
## its own effects with it.
func _revoke_node_effects(node: SkillNode, entity: Entity) -> void:
	if node == null or entity == null:
		return
	entity.revoke_effects_from(node)


func _is_adjacent_via_real_edge(a: SkillNode, b: SkillNode) -> bool:
	if a == null or b == null or a == b:
		return false
	return _real_neighbours(a).has(b)


## Nodes adjacent to [param node] via a real (non-self-loop) edge, ignoring
## ownership. Shared neighbour iterator for adjacency / BFS reachability.
func _real_neighbours(node: SkillNode) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if graph == null or node == null:
		return out
	for e in graph.get_edges():
		if e.from == e.to:
			continue  # self-loop never lands a move
		if e.from == node and e.to != null:
			out.append(e.to)
		elif e.to == node and e.from != null:
			out.append(e.from)
	return out


func _movement_budget(entity: Entity) -> int:
	if entity == null:
		return 0
	var board := entity.stat_board
	if board != null and board.movement_points != null:
		return board.movement_points.available()
	return 0


## Core movement (#21). Every owned node reachable from the current core slot
## within [param max_hops] mapped to its hop distance, excluding the core itself.
## Delegates to the entity's owned-subgraph mirror ([EntityNavigator]) — no
## bespoke BFS here; the mirror already knows the owned topology (and excludes
## self-loops). Drives the reachability highlight ([CoreMoveHighlightProvider]).
func reachable_core_landings(entity: Entity, max_hops: int) -> Dictionary:
	var result: Dictionary = {}
	if entity == null or entity.navigator == null or max_hops < 1:
		return result
	var source := entity.core_location
	if source == null:
		return result
	var within := entity.navigator.nodes_within(source, max_hops)
	for node in within:
		if node != source:
			result[node] = within[node]
	return result


## Core movement (#21). Fewest-hops owned-edge path (inclusive of both ends) from
## the current core slot to [param target], or [code][][/code] if [param target]
## is unreachable (not in the owned subgraph) or farther than the entity's
## remaining movement budget. Used to commit a multi-hop drag (chained single-hop
## `move_core`) and to paint the on-route edges. Delegates to the owned mirror.
func core_path(entity: Entity, target: SkillNode) -> Array[SkillNode]:
	var empty: Array[SkillNode] = []
	if entity == null or entity.navigator == null or target == null:
		return empty
	var source := entity.core_location
	if source == null or target == source:
		return empty
	var path := entity.navigator.path_between(source, target)
	if path.size() < 2:
		return empty
	if path.size() - 1 > _movement_budget(entity):
		return empty
	return path


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
