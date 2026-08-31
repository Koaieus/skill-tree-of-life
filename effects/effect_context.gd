class_name EffectContext
extends RefCounted

## The payload every [Effect] hook receives, and the only channel through which
## an effect touches the world. Effects never reach for autoloads or walk the
## scene tree — everything they need arrives here.
##
## [b]Grants are mid-life, not boundary-only.[/b] An effect may call [method grant]
## and [method revoke] from any hook, not just `_on_granted` — [AuraEffect] does
## exactly that as its buffed set shifts. The ledger on [member instance] tracks
## what is currently applied, so [method revoke_all] is always exact.
# TODO: need to carefully review all these splits -- both where/when these live,
	# as well as Effect vs EffectInstance. review: where does effect definition live, 
	# where/when does it get applied, and reapplied, like map out the whole lifecycle

## The owner slice this context acts through (#520). NOT an [Entity]: everything
## below that used to reach `entity.stat_board` / `entity.navigator` /
## `node.add_local_modifier` now reaches the slice instead, so the identical
## [Effect] code recomputes against a shadow board when handed a shadow slice.
## There is no preview branch in this file — the world is the parameter.
var combat: EntityCombat
var instance: EffectInstance


func _init(p_combat: EntityCombat, p_instance: EffectInstance) -> void:
	combat = p_combat
	instance = p_instance


## The real [Entity] behind [member combat] — IDENTITY only (attitude, display).
## An effect that wants to CHANGE something must go through [member combat], or
## a shadow recompute would write to the live entity.
var entity: Entity:
	get: return combat.real_entity() if combat != null else null

## The world [member combat] belongs to, so a grant aimed at a [SkillNode] lands
## on that node's slice in the same world rather than on the real node.
var world: CombatWorld:
	get: return combat.world() if combat != null else CombatWorld.live()


## The node that carries this effect (keystone / addon), or null for
## entity-wide effects such as a core class.
var source_node: SkillNode:
	get: return instance.source_node

## The entity's owned-subgraph mirror. The right scope for aura hop-distance:
## a path may not shortcut through territory the entity doesn't own.
## Typed as the base [GraphMirror] rather than [EntityNavigator] (#520): a live
## slice answers with the entity's real navigator, a shadow with its own
## manual-mode mirror over the set it still owns. Both are keyed by real
## [SkillNode]s, which is what lets an aura's whole distance computation stay in
## real-node space regardless of which world it is running in.
var navigator: GraphMirror:
	get: return combat.mirror() if combat != null else null

var core_location: SkillNode:
	get:
		if combat == null:
			return null
		var c := combat.core()
		return c.real() if c != null else null

## The whole-graph mirror — reach through anyone's territory. Only what an aura
## with GLOBAL scope wants; owned-scope work goes through [member navigator].
var graph: Graph:
	get:
		var nav := navigator
		return nav.graph if nav != null else null


## Duplicate [param mod], apply it to [param target], and record the handle.
##
## [param target] is null for the entity's stat board, or a [SkillNode] for a
## node-local (`node_board`) modifier. Returns the applied handle — the token
## [method revoke] takes back.
##
## The `.duplicate(true)` is done here, once, so the "formula-driven modifiers
## carry mutable per-entity binding state and must never be shared" gotcha
## (.claude/rules/stats-system.md) is impossible to get wrong from an effect.
func grant(mod: StatModifier, target: Variant = null) -> StatModifier:
	if mod == null or combat == null:
		return null
	return _apply(mod.duplicate(true), target)


## Scale [param mod]'s leaves by [param scale] BEFORE granting — the aura path.
##
## Must not scale the outer handle after [method grant] the way an earlier
## version did: [method StatBoard.add_modifier] flattens a
## [CompositeStatModifier] and binds each CHILD, so a post-bind write to the
## composite's own `value` lands on a vestigial field nothing reads again
## (#623). And on a clone/shadow board, [method StatBoard._localize] hands a
## formula-bearing modifier's binder a private copy — so even a plain
## modifier's post-bind write can land on an object nobody applied. Scaling
## the duplicate's flattened leaves first sidesteps both: whatever
## `add_modifier` / `add_local_modifier` binds afterward is already correct.
func grant_scaled(mod: StatModifier, scale: float, target: Variant = null) -> StatModifier:
	if mod == null or combat == null:
		return null
	var scaled: StatModifier = mod.duplicate(true)
	for leaf in scaled.flatten():
		leaf.value *= scale
	return _apply(scaled, target)


## Apply an already-duplicated (and, for [method grant_scaled], already-scaled)
## handle to its target and ledger it. The shared tail of [method grant] and
## [method grant_scaled] — the only difference between them is what happens to
## the duplicate before it gets here.
func _apply(handle: StatModifier, target: Variant) -> StatModifier:
	if target == null:
		var board := combat.board()
		if board == null:
			return null
		board.add_modifier(handle)
	else:
		var node: SkillNode = target
		if not is_instance_valid(node):
			return null
		var slice := world.combat_for(node)
		if slice == null:
			return null
		slice.add_local_modifier(handle)
	instance.record(handle, target)
	return handle


## Grant [param tag] to [param target] (null = entity-wide, a [SkillNode] =
## node-scoped). Refcounted on the carrier ([method SkillNode.add_tag] /
## [method Entity.add_tag]) — granting the same tag twice and revoking once
## leaves it active, because a second source is still relying on it. Ledgered
## alongside modifier grants (same [EffectInstance]), so [method revoke_all]
## sweeps both channels in one pass. Returns the token [method revoke] takes back.
func grant_tag(tag: StringName, target: Variant = null) -> Variant:
	if combat == null:
		return null
	if not _apply_tag(target, tag, 1):
		return null
	return instance.record_tag(tag, target)


## Remove a previously granted handle from wherever it landed — a [StatModifier]
## from [method grant], or a tag token from [method grant_tag]. Kind-polymorphic
## so callers don't need to remember which channel a handle came from.
func revoke(handle: Variant) -> void:
	if handle == null:
		return
	var row: Dictionary = instance.forget(handle)
	if row.is_empty():
		return
	if row.get(&"kind", &"modifier") == &"tag":
		_apply_tag(row[&"target"], row[&"tag"], -1)
	else:
		_detach(handle, row[&"target"])


## Revoke every grant, or (when [param target] is given) only those on that
## target. Pass the sentinel `false` to mean "all targets". Sweeps modifier
## and tag rows alike — one ledger, one pass.
func revoke_all(target: Variant = false) -> void:
	for row in instance.grants(target):
		var handle: Variant = row[&"handle"]
		instance.forget(handle)
		if row.get(&"kind", &"modifier") == &"tag":
			_apply_tag(row[&"target"], row[&"tag"], -1)
		else:
			_detach(handle, row[&"target"])


## Handles currently granted to [param target] — the aura's diff read. Keeps
## the effect resource stateless.
func handles_for(target: Variant) -> Array[StatModifier]:
	return instance.handles_for(target)


## The [StatBoard] a grant/revoke to [param target] would land on — the entity
## board for null, a [SkillNode]'s node board otherwise. Mirrors [method _apply]
## / [method _detach]'s own target routing (without duplicating it) so a caller
## can bracket a burst of grants/revokes to one target in
## [method StatBoard.begin_batch] / [method StatBoard.end_batch] (#627).
##
## Returns null when there is nothing to batch: no [member combat], a freed
## [param target], or a node whose board has never been touched (lazily
## materialized — [method SkillNode._init_node_board]'s "never pays for a
## board it doesn't need" rule). The caller's own grant/revoke still lazily
## creates and touches it in that case, just unbatched, exactly as today.
func board_for(target: Variant) -> StatBoard:
	if combat == null:
		return null
	if target == null:
		return combat.board()
	if not is_instance_valid(target):
		return null
	var node: SkillNode = target
	var slice := world.combat_for(node)
	return slice.board() if slice != null else null


## Hand [param board] to the running dispatch's batch ledger (#647), so every
## aura firing in the SAME hook dispatch shares one batch per board instead of
## opening its own. Returns `true` when the slice took ownership — the caller
## must not close it. `false` means no dispatch is live (`_on_granted`, a direct
## [method AuraEffect.recompute]), leaving the caller to bracket it itself.
##
## Routed through [member combat], never [member entity]: a shadow slice's
## [method EntityCombat.real_entity] answers with the LIVE entity, so an entity-
## addressed ledger would let a shadow recompute park shadow boards on a live
## entity that never drains them.
func hold_batch(board: StatBoard) -> bool:
	return combat.hold_batch(board) if combat != null else false


func _detach(handle: StatModifier, target: Variant) -> void:
	if combat == null:
		return
	if target == null:
		var board := combat.board()
		if board != null:
			board.remove_modifier(handle)
		return
	# Untyped read before validity check — a typed assignment of a freed
	# instance crashes first. See .claude/rules/godot-workflow.md.
	if not is_instance_valid(target):
		return
	var node: SkillNode = target
	var slice := world.combat_for(node)
	if slice != null:
		slice.remove_local_modifier(handle)


## Apply [param delta] (±1) to [param tag]'s refcount on [param target] (null =
## entity-wide). Returns false (and does nothing) if the target is gone —
## mirrors [method _detach]'s freed-node guard, since a cascade can free a node
## between grant and revoke.
func _apply_tag(target: Variant, tag: StringName, delta: int) -> bool:
	if combat == null:
		return false
	if target == null:
		if delta > 0:
			combat.add_tag(tag)
		else:
			combat.remove_tag(tag)
		return true
	if not is_instance_valid(target):
		return false
	var node: SkillNode = target
	var slice := world.combat_for(node)
	if slice == null:
		return false
	if delta > 0:
		slice.add_tag(tag)
	else:
		slice.remove_tag(tag)
	return true
