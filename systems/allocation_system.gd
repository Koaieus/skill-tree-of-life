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
## one. Slide-tween consumers (SkillNode's CorePresence, #128) subscribe here
## rather than to `core_location_changed` so they get the previous position too.
signal core_moved(entity: Entity, from_node: SkillNode, to_node: SkillNode)

@export var graph: Graph
@export var navigator: Navigator
@export var turn_manager: TurnManager

## The stake ceiling — the highest `stake_level` a node may reach (#337). One
## named constant so a balance pass is a one-number edit; the "4 as a special
## keystone" idea is future scope and gets no mechanism here.
const STAKE_CEILING := 3


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
		var board := n.owned_by.stat_board
		if board.skill_points != null:
			board.skill_points.claim(1)
		# This path bypasses force_allocate, so it must reproduce its side
		# effects itself — and in the SAME order, or the #376 local-scale
		# mutator sees a different world when the fill lands.
		#
		# The modifier push was missing until 2026-08-14: every hand-authored
		# owned node's `modifiers` were inert, so dev_sandbox's Right/Down
		# granted the player nothing. Pinned by
		# test_allocation.gd::test_scene_authored_ownership_applies_node_modifiers.
		n.apply_entity_modifiers_to(board)
		_grant_node_effects(n, n.owned_by)
		# Fill the first allocation slot LAST — the allocate path owns fill
		# writes (#337); this bypasses it, so it sets the 1 explicitly, after
		# the grants are applied (the mutator reads the board when it lands).
		n.allocation_level = 1


func can_allocate(node: SkillNode, entity: Entity) -> bool:
	if entity == null or node == null:
		return false
	if node.owned_by != null and (node.owned_by != entity or node.allocation_level >= node.stake_level):
		return false
	var board := entity.stat_board
	if board != null and board.skill_points != null and board.skill_points.available() < 1:
		return false
	# Refills need no adjacency — the node is already in the owned subgraph.
	if node.owned_by == null and _has_any_owned_node(entity) and not _is_adjacent_to_owned(node, entity):
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
	if node.owned_by == null:
		# First allocation: 0 → 1. ONLY this transition runs the full side
		# effect path — a refill must never re-apply modifiers or re-grant
		# effects (#337), or they would double-stack silently.
		node.owned_by = entity
		if entity.navigator != null:
			entity.navigator.mirror_add(node)
		node.apply_entity_modifiers_to(board)
		# Effects BEFORE the fill lands: the local-scale mutator (#376) walks
		# the effects on the 0→1 transition and must find the fresh grant.
		_grant_node_effects(node, entity)
		# Fill after the grants are applied (the mutator reads the board).
		node.allocation_level = 1
		# After the mirror update: an aura recomputing off this hook must see the
		# new node in the owned subgraph, not the stale one.
		entity.dispatch(&"_on_node_allocated", [node, false])
		allocated.emit(node, entity, false)
	else:
		# Refill: fill 1 → 2. Only spend + increment + visuals sync — no
		# re-grant, no mirror, no modifiers, no signal.
		node.allocation_level += 1
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
	# Effects BEFORE the fill lands: the local-scale mutator (#376) walks the
	# effects on the 0→1 transition and must find the fresh grant.
	_grant_node_effects(node, entity)
	# Fill the first allocation slot — the allocate path owns fill writes
	# (#337); this bypasses it, so it sets the 1 explicitly, after the grants
	# are applied (the mutator reads the board when the fill lands).
	node.allocation_level = 1
	entity.dispatch(&"_on_node_allocated", [node, true])
	allocated.emit(node, entity, true)


func deallocate(node: SkillNode, entity: Entity) -> bool:
	if not can_deallocate(node, entity):
		return false
	_deallocate_unchecked(node, entity)
	return true


## Shared post-gate body of [method deallocate] and [method deallocate_set].
## Assumes the caller has already validated ownership/core/budget — this does
## the actual strip + refund + signal, no gating of its own.
func _deallocate_unchecked(node: SkillNode, entity: Entity) -> void:
	var previous := node.owned_by
	# Snapshot the fill BEFORE ownership clears — owner_changed zeroes
	# allocation_level via _refresh_alloc_count, so a read after would return
	# 0 and under-refund the SP (the #337 ordering hazard; same shape as
	# LootSystem's pre-cleanup snapshot). A 2/2 node refunds 2 SP.
	var fill: int = node.allocation_level
	var board := entity.stat_board
	# Strip swapped effect-sets BEFORE the revoke sweep — the set leaves were
	# applied outside the effect ledger and would strand otherwise (#376).
	node.clear_scaled_effect_sets(board)
	_revoke_node_effects(node, entity)
	node.remove_entity_modifiers_from(board)
	if entity.navigator != null:
		entity.navigator.mirror_remove(node)
	node.owned_by = null
	# After the mirror drops the node and ownership clears — an aura recomputing
	# here must not still see the node as its own.
	entity.dispatch(&"_on_node_deallocated", [node, false])

	if board != null:
		if board.deallocation_points != null:
			board.deallocation_points.deplete(1)
		if board.skill_points != null:
			board.skill_points.refund(fill)
	deallocated.emit(node, previous)


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
	# Revoke sweep + navigator mirror removal (#498 step 1): lives on the
	# previous owner's EntityCombat slice now — see EntityCombat.revoke_node.
	previous.get_combat().revoke_node(node)
	node.owned_by = null
	previous.dispatch(&"_on_node_deallocated", [node, true])
	force_deallocated.emit(node, previous)
	return previous


# ── Mass allocate / deallocate: distant clicks + would-island confirm ───────
#
# A single click on an unowned node too far to allocate directly, or an owned
# node whose deallocation would island others, no longer just no-ops/rejects —
# PlayerInputController routes those through a confirm panel (`MassActionRequest`)
# and, on confirm, `mass_allocate` / `deallocate_set` below. Both compose the
# existing single-node primitives rather than reimplementing gating: allocation
# walks `allocate()` hop by hop (each hop becomes adjacent once its predecessor
# lands, so no bypass is needed); deallocation needs `_deallocate_unchecked`
# because the whole cascade is pre-vetted as a set and must NOT re-run
# `would_disconnect_from` per node mid-batch.

## FULL fewest-hop route from [param entity]'s owned frontier to [param target],
## over the GLOBAL mirror ([member navigator]). Impassable: nodes owned by
## anyone other than [param entity], and unrevealed nodes (no vision-leak via a
## distant-click preview). [] if [param target] is already owned, the entity has
## no owned frontier yet (first placement has no "distant" concept), or no route
## exists. Ordered frontier -> ... -> target (index 0 is the already-owned
## anchor; the new nodes to pay for are [code]path[1..][/code]).
func allocation_path(entity: Entity, target: SkillNode) -> Array[SkillNode]:
	var empty: Array[SkillNode] = []
	if entity == null or target == null or navigator == null or entity.navigator == null:
		return empty
	if target.owned_by != null:
		return empty
	var frontier := entity.navigator.get_mirrored_nodes()
	if frontier.is_empty():
		return empty
	var blocked: Array[SkillNode] = []
	for n in navigator.get_mirrored_nodes():
		if (n.owned_by != null and n.owned_by != entity) or not n.revealed:
			blocked.append(n)
	var reversed := navigator.shortest_path_to_any(target, frontier, blocked)
	if reversed.is_empty():
		return empty
	reversed.reverse()
	return reversed


## Executes [code]path[1 .. affordable_count][/code] via ordinary [method allocate]
## calls in sequence — each hop becomes adjacent to the entity's territory only
## once its predecessor has landed. Returns the count actually allocated (should
## equal [param affordable_count] barring a concurrent state change; stops early
## on the first unexpected failure rather than allocating out of order).
func mass_allocate(entity: Entity, path: Array[SkillNode], affordable_count: int) -> int:
	var allocated_count := 0
	for i in range(1, mini(affordable_count, path.size() - 1) + 1):
		if not allocate(path[i], entity):
			break
		allocated_count += 1
	return allocated_count


## The full doomed set a voluntary deallocate of [param node] would take with
## it: [param node] itself plus everything [param entity]'s owned subgraph would
## lose reachability to as a result (see [method GraphMirror.nodes_islanded_by_removing]).
## [] if [param node] isn't [param entity]'s or is the core (never part of a cascade).
func deallocation_cascade(node: SkillNode, entity: Entity) -> Array[SkillNode]:
	var empty: Array[SkillNode] = []
	if node == null or entity == null or node.owned_by != entity or node.is_core():
		return empty
	if entity.navigator == null:
		var single: Array[SkillNode] = [node]
		return single
	var cascade: Array[SkillNode] = [node]
	cascade.append_array(entity.navigator.nodes_islanded_by_removing(node, entity.core_location))
	return cascade


## DP budget check only for a pre-vetted [method deallocation_cascade] — ownership
## / core validity was already checked when the cascade was built, this just asks
## "can the entity afford all of it".
func can_deallocate_set(nodes: Array[SkillNode], entity: Entity) -> bool:
	if entity == null or nodes.is_empty():
		return false
	var board := entity.stat_board
	if board == null or board.deallocation_points == null:
		return false
	return board.deallocation_points.available() >= nodes.size()


## All-or-nothing bulk deallocate of a pre-vetted cascade (see
## [method deallocation_cascade]). Does NOT re-run `would_disconnect_from` per
## node — the set itself is the pre-vetted answer to "what would this take with
## it". Returns false (no mutation) if the DP budget doesn't cover the whole set.
func deallocate_set(nodes: Array[SkillNode], entity: Entity) -> bool:
	if not can_deallocate_set(nodes, entity):
		return false
	for n in nodes:
		if n.owned_by == entity:
			_deallocate_unchecked(n, entity)
	return true


# ── Staking (#337): raise a node's cap with SP+AP, reclaim with extract ──────
#
# `stake_level` is the cap N, `allocation_level` the fill M — a node reads M/N.
# stake raises the cap (SP current → staked + 1 AP); allocate fills it (SP
# spend); extract drops the cap back (1 DP, staked SP → current, plus the
# displaced fill's SP when the node was full). The `staked` bucket is a global
# per-entity reservation, coupled to caps by convention only — capturing an
# enemy's staked node and extracting it reclaims YOUR staked SP, not theirs
# (extract() caps at min(n, staked), so a never-staked entity gains nothing).

## Can this entity stake [param node] — raise its allocation cap by 1?
## Requires: ownership · core within 1 hop over the OWNED subgraph · ≥ 1 SP ·
## ≥ 1 AP · cap below the ceiling. Budget gates read `available()`, never
## `.current` (.claude/rules/stats-system.md).
func can_stake(node: SkillNode, entity: Entity) -> bool:
	if entity == null or node == null:
		return false
	if node.owned_by != entity:
		return false
	if node.stake_level >= STAKE_CEILING:
		return false
	if not _core_within_one_hop(node, entity):
		return false
	var board := entity.stat_board
	if board != null and board.skill_points != null and board.skill_points.available() < 1:
		return false
	if board != null and board.action_points != null and board.action_points.available() < 1:
		return false
	return true


## Raise [param node]'s allocation cap by 1: 1 SP moves current → staked,
## 1 AP is spent.
func stake(node: SkillNode, entity: Entity) -> bool:
	if not can_stake(node, entity):
		return false
	var board := entity.stat_board
	if board != null and board.skill_points != null:
		board.skill_points.stake(1)
	if board != null and board.action_points != null:
		board.action_points.deplete(1)
	node.stake_level += 1
	return true


## Can this entity extract [param node] — drop its cap by 1 and reclaim the
## staked SP? Requires: ownership · cap above 1 (a 1/1 node is a deallocate,
## not an extract) · core within 1 hop · ≥ 1 DP · ≥ 1 staked SP.
func can_extract(node: SkillNode, entity: Entity) -> bool:
	if entity == null or node == null:
		return false
	if node.owned_by != entity:
		return false
	if node.stake_level <= 1:
		return false
	if not _core_within_one_hop(node, entity):
		return false
	var board := entity.stat_board
	if board != null and board.deallocation_points != null and board.deallocation_points.available() < 1:
		return false
	if board != null and board.skill_points != null and board.skill_points.staked < 1:
		return false
	return true


## Drop [param node]'s cap by 1. Costs 1 DP. Refunds the staked SP; when the
## node was full (fill == cap) the displaced fill's SP is refunded too, so a
## 2/2 extract yields 1/1. The fill steps down with the cap through the pool's
## clamp (cap fall clamps current).
func extract(node: SkillNode, entity: Entity) -> bool:
	if not can_extract(node, entity):
		return false
	var board := entity.stat_board
	# Displaced fill: snapshot BEFORE the cap drops — the pool clamps the fill
	# down on cap fall, and the refunded SP must match.
	var fill: int = node.allocation_level
	var displaced := 1 if fill >= node.stake_level else 0
	if board != null:
		if board.deallocation_points != null:
			board.deallocation_points.deplete(1)
		if board.skill_points != null:
			board.skill_points.extract(1)
			if displaced > 0:
				board.skill_points.refund(displaced)
	node.stake_level -= 1
	return true


## True when the entity's core is within 1 hop of [param node] over the OWNED
## subgraph — the core itself (0 hops) or an immediate neighbour. One BFS via
## the mirror's gather ([method GraphMirror.nodes_within]), never a
## per-candidate predicate (.claude/rules/graph.md). Fails closed without a
## navigator.
func _core_within_one_hop(node: SkillNode, entity: Entity) -> bool:
	if entity == null or entity.navigator == null or entity.core_location == null:
		return false
	return entity.navigator.nodes_within(entity.core_location, 1).has(node)


## Core movement (#21). Validates `move_core` preconditions without committing.## - target must be owned by the entity (you only hop across your own subgraph)
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
## the existing `core_location_changed` (for the CorePresence swap, vision
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
	# `get_neighbours` is the cached adjacency index; the hand-rolled edge walk
	# this replaced rebuilt every Edge in the level per call (graph.md). The
	# self-loop filter stays: the index lists a self-loop as the node itself
	# (twice), and a self-loop never lands a move.
	for other in graph.get_neighbours(node):
		if other != null and other != node:
			out.append(other)
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
	# The navigator IS the entity's owned subgraph, so a non-empty mirror
	# answers this in O(1) instead of scanning the whole board — and
	# `can_allocate` is called once per node by NodeHighlightOverlay on every
	# repaint, which made the scan quadratic in the board and re-fired on every
	# alloc/dealloc/SP change.
	#
	# ONE-SIDED on purpose. An EMPTY mirror is not proof the entity owns
	# nothing: EntityNavigator's contract is that ownership writes go through
	# this system, and a direct `node.owned_by = X` (tests do it, and it is how
	# scene-authored ownership arrives before `wire_to`'s bootstrap sweep)
	# leaves the mirror stale. Trusting an empty mirror would make this return
	# false and drop `can_allocate`'s adjacency requirement entirely — the gate
	# failing OPEN, letting a click allocate a node nowhere near your territory.
	# So the fast path only takes the positive answer; the negative falls back.
	if entity != null and entity.navigator != null \
			and not entity.navigator.get_mirrored_nodes().is_empty():
		return true
	if graph == null:
		return false
	for n in graph.get_skill_nodes():
		if n.owned_by == entity:
			return true
	return false


func _is_adjacent_to_owned(node: SkillNode, entity: Entity) -> bool:
	if graph == null:
		return false
	# Cached adjacency index, not a full edge rebuild per candidate node — same
	# quadratic-repaint path as `_has_any_owned_node` above.
	for other in graph.get_neighbours(node):
		if other != null and other != node and other.owned_by == entity:
			return true
	return false
