class_name CombatWorld
extends RefCounted

## The world an [AttackOutcome] lands in (#498 step 3 — see
## docs/domain/attack-timeline.md). One indirection, and the whole of what
## `resolve_against(slice)` turned out to mean for the landing half: every
## [method HitInstance.land_on] takes a [NodeCombat], and this is what turns the
## [SkillNode] a hit NAMES into the [NodeCombat] it MUTATES.
##
## [codeblock]
## real launch / peer replay:  OutcomeApplier.apply(outcome, CombatWorld.live(), clock)
## AI scoring / preview:       OutcomeApplier.apply(outcome, CombatWorld.shadow(), clock)
## [/codeblock]
##
## [b]Why [member HitInstance.target] stays a [SkillNode].[/b] A hit's target is
## its IDENTITY — what [AttackRecord] serializes, what a fogged peer resolves by
## `stable_id`, what every VFX observer reads. Retyping it would have made the
## shadow visible to a dozen files that have no business knowing one exists.
## State is the thing that must be swappable, so the swap lives here, in one
## lookup, and identity is left alone.
##
## [b]Why one class rather than a per-entity slice.[/b] An attack — a propagating
## spell above all — crosses territory belonging to several entities, and a
## [method EntityCombat.snapshot] is per-entity by construction. This holds as
## many of those as the attack turns out to touch, plus ownerless slices for the
## unallocated nodes a spell only uses as conduits, under one
## [SkillNode] -> [NodeCombat] index.
##
## [b]A shadow grows on demand, and that is safe.[/b] [method shadow] starts
## empty. The first time a hit lands on a node whose owner is not snapshotted
## yet, that owner's [EntityCombat] is snapshotted then — its entity board, its
## owned-set mirror, its effect twins and its core's board — and from #695 on
## each further owned NODE's board is cloned only when this world is first asked
## about that node ([method EntityCombat.shadow_for]). Snapshotting late reads
## the same state as snapshotting up front, because a shadow resolve never
## writes to the real world, so the real world is frozen for its whole duration.
## Lazily is also strictly cheaper: at ~0.7 ms per entity board (the bench on
## #498) only the entities actually hit are paid for, and at ~0.1 ms per node
## board only the nodes a walk actually visits (#681 measured 8-24 ms per hover
## for the whole-subgraph clone this replaced).
##
## Per-node laziness ends the moment anything ENTITY-wide runs — a cascade, a
## simulated death, a hook dispatch, an `owned()` read — at which point
## [method EntityCombat._materialize_all] mints the rest, so #498's "do not
## reach-bound the owned subgraph" still holds: a node fifty hops away is in the
## cascade set exactly as before, because by the time a cascade set is asked for
## the whole subgraph is present (owner call on #695, 2026-08-31).
##
## [b]Every shadow needs [method free_shadow][/b], for the reference cycles
## [method EntityCombat.free_shadow] documents. A live world holds nothing and
## frees nothing.

## Live singleton — stateless, so one instance serves every caller and the
## default argument on [method OutcomeApplier.apply] costs no allocation.
static var _live: CombatWorld = null

## True for a world backed by shadow slices. The one thing outside this class
## that reads it is the melee pop cue ([BladePopResolver.LiveGate]) — an
## announcement, which a shadow must not make, exactly like [member SkillNode]'s
## `host != null` branch.
var _shadow: bool = false
var _nodes: Dictionary[SkillNode, NodeCombat] = {}
var _entities: Dictionary[Entity, EntityCombat] = {}
## Ownerless slices minted for unallocated conduit nodes — held apart from
## [member _entities] because no [EntityCombat] will release their boards.
var _orphans: Array[NodeCombat] = []


## The real world. Every lookup delegates to the live slice each object already
## composes, so this adds no state and cannot go stale.
static func live() -> CombatWorld:
	if _live == null:
		_live = CombatWorld.new()
	return _live


## A detached world. Nothing is snapshotted until something is asked for — see
## the class doc on why growing on demand is both safe and cheaper.
static func shadow() -> CombatWorld:
	var w := CombatWorld.new()
	w._shadow = true
	return w


func is_shadow() -> bool:
	return _shadow


## The [NodeCombat] that [param node]'s state lives in for this world.
##
## Live: the node's own composed slice. Shadow: the snapshot, taken now if this
## is the first time this world has been asked about [param node] — and its
## owner's entity-level snapshot too, if this is the first of that owner's
## nodes (see the class doc). An unallocated node gets an ownerless slice of
## its own — a spell conduit has no entity to snapshot, but it still has a
## board a hit could read or mutate.
func combat_for(node: SkillNode) -> NodeCombat:
	if node == null:
		return null
	if not _shadow:
		return node.get_combat()
	var known: NodeCombat = _nodes.get(node)
	if known != null:
		return known
	var owner_entity := node.owned_by
	if owner_entity != null:
		# Mints just THIS node's board (#695) — `shadow_for` registers it here
		# through `index_node`. Null when the owner's navigator disagrees with
		# `owned_by` (a fixture that wrote the field directly), which falls
		# through to an orphan exactly as the whole-subgraph fold did.
		known = combat_for_entity(owner_entity).shadow_for(node)
		if known != null:
			return known
	var orphan := node.get_combat().snapshot(null)
	_nodes[node] = orphan
	_orphans.append(orphan)
	return orphan


## The [EntityCombat] that [param entity]'s state lives in for this world.
## Shadow: snapshotted on first ask; its owned nodes join this world's node
## index one at a time as they are minted ([method index_node]).
func combat_for_entity(entity: Entity) -> EntityCombat:
	if entity == null:
		return null
	if not _shadow:
		return entity.get_combat()
	var known: EntityCombat = _entities.get(entity)
	if known != null:
		return known
	# `self` is handed IN rather than assigned after: an EffectContext resolves a
	# SkillNode grant target through its slice's world, and a snapshot's effect
	# twins are live from the moment they exist.
	var shadow_entity := entity.get_combat().snapshot(self)
	adopt(shadow_entity)
	return shadow_entity


## Register an already-built shadow [EntityCombat] and fold the nodes it has
## minted so far into this world's index. Called by [method combat_for_entity],
## and by [method EntityCombat.world] when a bare snapshot mints its own world —
## the case that needs the fold: nodes minted before the shadow had a world to
## [method index_node] into.
func adopt(shadow_entity: EntityCombat) -> void:
	if shadow_entity == null or not _shadow:
		return
	var origin := shadow_entity.real_entity()
	if origin != null:
		_entities[origin] = shadow_entity
	var index := shadow_entity.shadow_index()
	for real_node in index:
		index_node(real_node, index[real_node])


## Index one minted shadow node under its real node. Called by
## [method EntityCombat.shadow_for] as it mints (#695), so a node's slice is
## findable from this world the moment it exists — an [EffectContext] resolves a
## grant target through here.
func index_node(real_node: SkillNode, slice: NodeCombat) -> void:
	if real_node == null or slice == null or not _shadow:
		return
	# An owned node can never have been minted as an orphan first —
	# `combat_for` checks `owned_by` before it orphans, and ownership does
	# not change under a shadow except by a cascade, which only ever un-owns.
	_nodes[real_node] = slice


## Release every slice this world minted. Mandatory on a shadow (see
## [method EntityCombat.free_shadow] for the [RefCounted] cycles involved) and a
## no-op on the live world, which minted nothing.
func free_shadow() -> void:
	if not _shadow:
		return
	# Taken and cleared FIRST: EntityCombat.free_shadow hands a world it minted
	# itself back to this method, so re-entry has to find nothing left to do.
	var entities: Array = _entities.values()
	_entities.clear()
	for shadow_entity in entities:
		shadow_entity.free_shadow()
	for orphan in _orphans:
		if orphan._board != null:
			orphan._board.release()
			orphan._board = null
		orphan._real = null
	_orphans.clear()
	_entities.clear()
	_nodes.clear()
