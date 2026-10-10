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
## A staking channel started on [param node], or its target moved one step
## further (a mid-channel stake / extract). Read the node's channel fields.
signal channel_changed(node: SkillNode)
## One channel step landed: `stake_level` moved by [param direction] (±1).
signal channel_stepped(node: SkillNode, direction: int)
## A channel closed — exactly once per channel. [param reason] is `&"landed"`
## (target reached), `&"leash"`, `&"ownership"` or `&"cancelled"`;
## [param previous_owner] is the owner the channel ran for, set even when the
## reason is ownership loss.
signal channel_ended(node: SkillNode, previous_owner: Entity, reason: StringName)

@export var graph: Graph
@export var navigator: Navigator
@export var turn_manager: TurnManager:
	set = _set_turn_manager

@export_group("Staking channels")
## Initiation radius in px: stake / extract need the target node's position
## within this distance of the core node's. Tentative, easy to change.
@export var stake_reach_px: float = 250.0
## Leash = reach × this ratio; a core arrival beyond it aborts the entity's
## channels. Clamped to ≥ 1 so anything initiable starts inside its leash.
## Tentative, easy to change.
@export_range(1.0, 4.0, 0.05, "or_greater") var stake_leash_ratio: float = 2.0:
	set(value):
		stake_leash_ratio = maxf(value, 1.0)
## Owner real-turn-starts per landed stake step. Tentative, easy to change.
@export_range(1, 10, 1, "or_greater") var stake_channel_turns: int = 2
## Owner real-turn-starts per landed extract step. Tentative, easy to change.
@export_range(1, 10, 1, "or_greater") var extract_channel_turns: int = 3
## SP pledged (current → staked) per stake step, at initiation.
@export_range(0, 5, 1, "or_greater") var stake_sp_cost: int = 1
## Staked SP lost (staked → wounded) per landed extract step.
@export_range(0, 5, 1, "or_greater") var extract_sp_refund: int = 1
@export_group("")


func _ready() -> void:
	Events.entity_died.connect(_on_entity_died)


## Death cleanup (#18): strip a dead entity of every node it owns. Runs
## SYNCHRONOUSLY even though death can fire mid-cascade — a cascade chip inside
## [method EntityCombat.apply_cascade] (or SkillNode.take_damage) crosses
## `health` 0 → `depleted` → Entity.die() → this. That's safe: apply_cascade
## re-checks `owner() != self` per node, so nodes stripped here are skipped when
## control returns to the outer loop — no double strip, no restart.
## Synchronous is deliberately chosen over deferring: a deferred
## `deallocate_all_owned(entity)` races GameRoot freeing the corpse, and a
## deferred call whose Object arg is freed is dropped, orphaning the nodes
## (owned_by a freed entity). See test_npc_death_via_bus_deallocates_before_free.
func _on_entity_died(entity: Entity) -> void:
	deallocate_all_owned(entity)


## Strip every node the entity owns through the one cascade driver,
## [method EntityCombat.apply_cascade] with `charge` false (no wounds, no chip),
## exactly as a shadow's [method EntityCombat.simulate_entity_death] does — so
## VFX shatter + `force_deallocated` fire per node via [method force_deallocate].
## The core node goes last — this is the only path that ever force-deallocates a
## core. Public so concede / despawn flows can reuse it.
func deallocate_all_owned(entity: Entity) -> void:
	if entity == null or graph == null:
		return
	entity.get_combat().apply_cascade(_owned_core_last(entity), self, false)
	# No flush: every death is inside a beat that flushes (a hit's schedule
	# group, the turn-end tick step, a gate-flip command), and flushing here
	# would split that beat's removed union.


## [param entity]'s owned [NodeCombat]s in graph order, its core moved last.
func _owned_core_last(entity: Entity) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	var core := entity.core_location
	for n in graph.get_skill_nodes():
		if n != core and n.owned_by == entity:
			out.append(n.get_combat())
	if core != null and core.owned_by == entity:
		out.append(core.get_combat())
	return out


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
	if node.owned_by == null and _has_any_owned_node(entity) \
			and (entity.navigator == null or not entity.navigator.borders(node)):
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


## Resets [param node]'s node-local `spikes` pool to full on an OWNERSHIP
## CHANGE (#778) — "a spent budget is not a trophy for the next allocator."
## Called from the 0 -> 1 transition in both [method allocate] and
## [method force_allocate], never from a same-owner restake. A no-op when
## the node never minted a `spikes` pool (unspiked — only [SpikeRingAddon]
## mints one).
func _restore_spikes_to_full(node: SkillNode) -> void:
	var b := node.get_combat().board()
	var pool := b.get_stat(&"spikes") as PoolStat if b != null else null
	if pool != null:
		pool.restore_to_full()


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
		_restore_spikes_to_full(node)
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
	_restore_spikes_to_full(node)
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


## Gating-free fill primitive (#915): raise an OWNED node's fill from its
## current `allocation_level` to [param level], one step at a time — the same
## `allocation_level += 1` write the refill branch of [method allocate] uses,
## so the #376 local-scale mutator only ever sees adjacent `(al, al+1)` jumps
## and `addon_slots` follows. Like the refill branch it re-grants nothing and
## emits no `allocated` — the 0→1 transition already did that. Never claims
## SP: the fill is free (a procgen pre-stake, not a purchase), so the entity's
## pool does not grow — a killed blocker is only ever `force_deallocate`d,
## which refunds nothing. Preconditions: owned, `allocation_level <= level <=
## stake_level`; lowering is not supported. Violations push_error and no-op.
func force_fill(node: SkillNode, level: int) -> void:
	if node == null:
		push_error("force_fill: null node")
		return
	if node.owned_by == null:
		push_error("force_fill(%s, %d): node is unowned — force_allocate first" % [node.name, level])
		return
	if level < 1 or level > node.stake_level:
		push_error("force_fill(%s, %d): level outside 1..stake_level (%d)" % [node.name, level, node.stake_level])
		return
	if level < node.allocation_level:
		push_error("force_fill(%s, %d): lowering from %d is not supported" % [node.name, level, node.allocation_level])
		return
	while node.allocation_level < level:
		node.allocation_level += 1


func deallocate(node: SkillNode, entity: Entity) -> bool:
	if not can_deallocate(node, entity):
		return false
	_deallocate_unchecked(node, entity)
	CombatWorld.live().flush_removals()
	return true


## Shared post-gate body of [method deallocate] and [method deallocate_set].
## Assumes the caller has already validated ownership/core/budget — this does
## the actual strip + refund + signal, no gating of its own.
func _deallocate_unchecked(node: SkillNode, entity: Entity) -> void:
	var previous := node.owned_by
	# Statuses are node-local and void on any ownership loss (#879, owner
	# 2026-09-14: "poison/blind/armor break -> remove effect upon dealloc").
	# Released before the strip below so nothing downstream reads a status the
	# node no longer legitimately holds, and noted while `owned_by` is still
	# set — the collector snapshots the masked neighbours a spill lands on.
	# The command that called this flushes ([method deallocate] / [method deallocate_set]).
	# `LINGER` rows survive the dealloc and are not spilled (#1344).
	_abort_channel(node, &"ownership")
	var combat := node.get_combat()
	CombatWorld.live().note_removed(combat, combat.release_statuses(true), StatusSpread.CAUSE_DEALLOC)
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
	_abort_channel(node, &"ownership")
	# Statuses void on any ownership loss (#879). A cascade has already
	# released and noted them (EntityCombat.apply_cascade, the spill feeder),
	# so this is the net for a direct caller, which drops them unspilled.
	# Re-entrancy: a poison tick can force_deallocate the very node being
	# ticked, and release_statuses() tolerates a slice already mid-iteration.
	# `LINGER` rows survive (#1344); a cascade has released them already.
	node.get_combat().release_statuses(true)
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


## How many hops of [param path] this entity can pay for right now — the
## [param affordable_count] [method mass_allocate] wants, computed in ONE place.
##
## Both callers need it and neither may own it: [PlayerInputController] shows it
## on the confirm panel before anything is submitted, and [CommandApplier]
## RE-computes it at apply time because [MassAllocateCommand] deliberately does
## not carry it (a stale sender must not dictate how much the authority spends,
## #458). Two hand-copies of `mini(path.size() - 1, sp)` would be exactly the
## parallel-mirror this repo keeps getting bitten by.
func affordable_allocation_count(entity: Entity, path: Array[SkillNode]) -> int:
	if entity == null or path.size() < 2:
		return 0
	var board := entity.stat_board
	if board == null or board.skill_points == null:
		return 0
	return mini(path.size() - 1, board.skill_points.available())


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
	# One command, one beat: the spill sees the whole set as removed.
	CombatWorld.live().flush_removals()
	return true


# ── Gates: flip, then cascade what the core can no longer reach ─────────────

## PREVIEW: the owned nodes [param entity] would lose if every gate in
## [param gates] flipped at once — the set [method apply_gate_flip] strands.
func gate_flip_cascade(gates: Array[Gate], entity: Entity) -> Array[SkillNode]:
	if entity == null or entity.navigator == null or entity.core_location == null:
		return [] as Array[SkillNode]
	return entity.navigator.nodes_islanded_by_flipping(gates, entity.core_location)


## APPLY (authority / direct caller): flip every gate, THEN judge connectivity
## once, then force-deallocate the stranded set with the normal charge. Returns
## the stranded set.
func apply_gate_flip(gates: Array[Gate], entity: Entity) -> Array[SkillNode]:
	var stranded: Array[SkillNode] = []
	var g := _graph_of(gates)
	if g == null:
		return stranded
	g.flip_gates(gates)
	if entity != null and entity.navigator != null and entity.core_location != null:
		# An empty removal set already means "owned nodes the core cannot reach".
		stranded = entity.navigator.nodes_islanded_by_removing_set([], entity.core_location)
	_cascade_stranded(stranded, entity)
	return stranded


## APPLY (replay): flip every gate and cascade the RECORDED [param stranded]
## set without re-walking — a peer applies what the authority stamped.
func apply_gate_flip_recorded(gates: Array[Gate], entity: Entity,
		stranded: Array[SkillNode]) -> void:
	var g := _graph_of(gates)
	if g == null:
		return
	g.flip_gates(gates)
	_cascade_stranded(stranded, entity)


## A self-cut is permitted and charged like a combat cascade: forced
## deallocation through [method EntityCombat.apply_cascade] with charge = true
## (wound + core-HP chip; the cascade releases and notes the statuses).
func _cascade_stranded(stranded: Array[SkillNode], entity: Entity) -> void:
	if entity == null or stranded.is_empty():
		return
	var combats: Array[NodeCombat] = []
	for n in stranded:
		if n != null and n.owned_by == entity and not n.is_core():
			combats.append(n.get_combat())
	entity.get_combat().apply_cascade(combats, self, true)


func _graph_of(gates: Array[Gate]) -> Graph:
	if graph != null:
		return graph
	for gate in gates:
		if gate != null and gate.get_graph() != null:
			return gate.get_graph()
	return null


# ── Staking channels: raise / lower a node's cap one step per K turns ────────
#
# `stake_level` is the cap N, `allocation_level` the fill M — a node reads M/N.
# stake / extract never move the cap directly: they open (or extend) a channel
# toward `channel_target`, which steps once per K of the owner's real turn
# starts ([method advance_channels]). stake pledges its SP at initiation
# (current → staked); extract pays its 1 DP at initiation. A landed extract
# step moves `extract_sp_refund` staked → wounded and refunds the displaced
# fill when the node was full. Reach is Euclidean px from the core node; the
# leash (reach × ratio) is checked only on a core ARRIVAL in [method move_core]
# — the tick never measures. Any abort (leash, ownership loss, cancel) wounds
# the still-pledged SP and forfeits a paid DP; landed steps stay. The `staked`
# bucket is a global per-entity reservation, coupled to caps by convention
# only. See docs/domain/allocation_system.md.

## Can this entity stake [param node] — open or extend a channel one cap up?
## True exactly when [method stake_denial] names no reason.
func can_stake(node: SkillNode, entity: Entity) -> bool:
	return stake_denial(node, entity) == &""


## Why [param entity] may not stake [param node]: the `node_action_denied`
## reason key of the first failing gate, or `&""` when the stake is allowed.
## Gates, in order: ownership · not channelling down · effective cap (the
## target while channelling) below the node's `stake_ceiling` · within
## [member stake_reach_px] of the core · SP ≥ [member stake_sp_cost]. Budget
## gates read `available()`, never `.current` (.claude/rules/stats-system.md).
## A null node or entity is the generic `stake_denied`.
func stake_denial(node: SkillNode, entity: Entity) -> StringName:
	if entity == null or node == null:
		return &"stake_denied"
	if node.owned_by != entity:
		return &"stake_denied_not_owned"
	if node.channel_direction() < 0:
		return &"stake_denied_channelling"
	if _effective_cap(node) >= node.stake_ceiling:
		return &"stake_denied_at_ceiling"
	if not _in_reach(node, entity):
		return &"stake_denied_not_adjacent"
	var board := entity.stat_board
	if board != null and board.skill_points != null \
			and board.skill_points.available() < stake_sp_cost:
		return &"stake_denied_no_sp"
	return &""


## Open (or extend) a stake channel on [param node]: [member stake_sp_cost] SP
## moves current → staked now, the target rises one above the effective cap.
func stake(node: SkillNode, entity: Entity) -> bool:
	if not can_stake(node, entity):
		return false
	var board := entity.stat_board
	if board != null and board.skill_points != null and stake_sp_cost > 0:
		board.skill_points.stake(stake_sp_cost)
	node.channel_target = _effective_cap(node) + 1
	channel_changed.emit(node)
	return true


## Can this entity extract [param node] — open or extend a channel one cap
## down? True exactly when [method extract_denial] names no reason.
func can_extract(node: SkillNode, entity: Entity) -> bool:
	return extract_denial(node, entity) == &""


## Why [param entity] may not extract [param node]: the `node_action_denied`
## reason key of the first failing gate, or `&""` when the extract is allowed.
## Gates, in order: ownership · not channelling up · effective cap above 1 (a
## 1/1 node is a deallocate, not an extract) · addons fit the lowered target
## cap · within [member stake_reach_px] of the core · ≥ 1 DP · staked ≥
## [member extract_sp_refund]. A null node or entity is the generic
## `extract_denied`.
func extract_denial(node: SkillNode, entity: Entity) -> StringName:
	if entity == null or node == null:
		return &"extract_denied"
	if node.owned_by != entity:
		return &"extract_denied_not_owned"
	if node.channel_direction() > 0:
		return &"extract_denied_channelling"
	var cap := _effective_cap(node)
	if cap <= 1:
		return &"extract_denied_at_floor"
	# Slots shrink with the cap: the lowered target loses `stake_level − (cap − 1)`.
	var slots_after := int(node.get_local_value(&"addon_slots")) - (node.stake_level - (cap - 1))
	if node.get_addon_count() > slots_after:
		return &"extract_denied_addon_overflow"
	if not _in_reach(node, entity):
		return &"extract_denied_not_adjacent"
	var board := entity.stat_board
	if board != null and board.deallocation_points != null and board.deallocation_points.available() < 1:
		return &"extract_denied_no_dp"
	if board != null and board.skill_points != null \
			and board.skill_points.staked < maxi(extract_sp_refund, 1):
		return &"extract_denied_no_staked_sp"
	return &""


## Open (or extend) an extract channel on [param node]: 1 DP is paid now, the
## target drops one below the effective cap. The SP exchange lands per step.
func extract(node: SkillNode, entity: Entity) -> bool:
	if not can_extract(node, entity):
		return false
	var board := entity.stat_board
	if board != null and board.deallocation_points != null:
		board.deallocation_points.deplete(1)
	node.channel_target = _effective_cap(node) - 1
	channel_changed.emit(node)
	return true


## The cap a verb builds on: the channel's target while one is open, else
## `stake_level`.
func _effective_cap(node: SkillNode) -> int:
	return node.channel_target if node.channel_target != 0 else node.stake_level


## Euclidean reach from the core node, on logical positions (identical on every
## peer). Fails closed without a core.
func _in_reach(node: SkillNode, entity: Entity) -> bool:
	var core := entity.core_location
	if core == null:
		return false
	return core.global_position.distance_squared_to(node.global_position) \
			<= stake_reach_px * stake_reach_px


## The leash radius in px: reach × ratio, never below reach.
func stake_leash_px() -> float:
	return stake_reach_px * maxf(stake_leash_ratio, 1.0)


## Progress toward [param node]'s next step as a fraction of its direction's
## K; 0 when idle. AllocationSystem owns K — a visual never re-derives it.
func channel_fraction(node: SkillNode) -> float:
	if node == null or not node.is_channelling():
		return 0.0
	return float(node.channel_progress) / float(maxi(_channel_turns(node.channel_direction()), 1))


func _channel_turns(direction: int) -> int:
	return stake_channel_turns if direction > 0 else extract_channel_turns


func _set_turn_manager(value: TurnManager) -> void:
	if turn_manager != null and turn_manager.real_turn_started.is_connected(advance_channels):
		turn_manager.real_turn_started.disconnect(advance_channels)
	turn_manager = value
	if turn_manager != null and not turn_manager.real_turn_started.is_connected(advance_channels):
		turn_manager.real_turn_started.connect(advance_channels)


## One served turn of [param entity]: every owned channelling node counts one
## tick; at K the step lands. No distance check — the leash is arrival-checked.
func advance_channels(entity: Entity) -> void:
	if entity == null or graph == null:
		return
	for node in graph.get_skill_nodes():
		if node.owned_by != entity or not node.is_channelling():
			continue
		var dir := node.channel_direction()
		node.channel_progress += 1
		if node.channel_progress < maxi(_channel_turns(dir), 1):
			continue
		node.channel_progress = 0
		_land_step(node, entity, dir)
		channel_stepped.emit(node, dir)
		if node.stake_level == node.channel_target:
			node.channel_target = 0
			channel_ended.emit(node, entity, &"landed")


## One step of the cap. Up: the SP was pledged at initiation. Down: the
## refund's staked SP is wounded and a full node's displaced fill refunded —
## snapshot BEFORE the cap drops, the pool clamps the fill on cap fall.
func _land_step(node: SkillNode, entity: Entity, dir: int) -> void:
	if dir > 0:
		node.stake_level += 1
		return
	var displaced := 1 if node.allocation_level >= node.stake_level else 0
	var board := entity.stat_board
	if board != null and board.skill_points != null:
		board.skill_points.wound_staked(extract_sp_refund)
		if displaced > 0:
			board.skill_points.refund(displaced)
	node.stake_level -= 1


## Close [param node]'s channel without landing: a stake's still-pledged SP
## goes staked → wounded on the owner's board; a paid extract DP stays spent.
## Call before `owned_by` clears so the previous owner is the one wounded.
func _abort_channel(node: SkillNode, reason: StringName) -> void:
	if node == null or not node.is_channelling():
		return
	var owner := node.owned_by
	var pledged := (node.channel_target - node.stake_level) * stake_sp_cost
	node.channel_target = 0
	node.channel_progress = 0
	if pledged > 0 and owner != null and owner.stat_board != null \
			and owner.stat_board.skill_points != null:
		owner.stat_board.skill_points.wound_staked(pledged)
	channel_ended.emit(node, owner, reason)


## Can [param entity] cancel the channel on [param node]? No reach gate.
func can_cancel_channel(node: SkillNode, entity: Entity) -> bool:
	return cancel_channel_denial(node, entity) == &""


## Gates, in order: ownership · an open channel. A null node or entity is the
## generic `cancel_denied`.
func cancel_channel_denial(node: SkillNode, entity: Entity) -> StringName:
	if entity == null or node == null:
		return &"cancel_denied"
	if node.owned_by != entity:
		return &"cancel_denied_not_owned"
	if not node.is_channelling():
		return &"cancel_denied_idle"
	return &""


## Abort [param node]'s channel with reason `&"cancelled"`.
func cancel_channel(node: SkillNode, entity: Entity) -> bool:
	if not can_cancel_channel(node, entity):
		return false
	_abort_channel(node, &"cancelled")
	return true


## Abort every channel of [param entity] whose node lies beyond the leash of
## its current core — called on each core arrival.
func _check_leash(entity: Entity) -> void:
	var core := entity.core_location
	if core == null or graph == null:
		return
	var leash := stake_leash_px()
	for node in graph.get_skill_nodes():
		if node.owned_by == entity and node.is_channelling() \
				and core.global_position.distance_squared_to(node.global_position) > leash * leash:
			_abort_channel(node, &"leash")


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
	# An arrival is the only moment the leash is measured (positions are fixed).
	_check_leash(entity)
	core_moved.emit(entity, from_node, target)
	return true


## Grant every [Effect] a node carries to its new owner (#4): the node's own
## [member SkillNode.effects] (a behavioural landmark's authored effect, a
## rolled [SpellGrant]) and any addon-borne effects.
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


## Adjacent over a real (non-self-loop) edge, ignoring ownership — the
## whole-board mirror's answer. `are_adjacent` already rejects `a == b`, so a
## self-loop never lands a move.
func _is_adjacent_via_real_edge(a: SkillNode, b: SkillNode) -> bool:
	if graph == null or graph.navigator == null:
		return false
	return graph.navigator.are_adjacent(a, b)


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
