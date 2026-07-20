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

var entity: Entity
var instance: EffectInstance


func _init(p_entity: Entity, p_instance: EffectInstance) -> void:
	entity = p_entity
	instance = p_instance


## The node that carries this effect (keystone / addon), or null for
## entity-wide effects such as a core class.
var source_node: SkillNode:
	get: return instance.source_node

## The entity's owned-subgraph mirror. The right scope for aura hop-distance:
## a path may not shortcut through territory the entity doesn't own.
var navigator: EntityNavigator:
	get: return entity.navigator if entity != null else null

var core_location: SkillNode:
	get: return entity.core_location if entity != null else null

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
	if mod == null or entity == null:
		return null
	var handle: StatModifier = mod.duplicate(true)
	if target == null:
		if entity.stat_board == null:
			return null
		entity.stat_board.add_modifier(handle)
	else:
		var node: SkillNode = target
		if not is_instance_valid(node):
			return null
		node.add_local_modifier(handle)
	instance.record(handle, target)
	return handle


## Scale a modifier's value before granting it — the aura path. Equivalent to
## grant() on a copy whose `value` is multiplied by [param scale].
func grant_scaled(mod: StatModifier, scale: float, target: Variant = null) -> StatModifier:
	if mod == null:
		return null
	var handle: StatModifier = grant(mod, target)
	if handle != null:
		handle.value = mod.value * scale
	return handle


## Grant [param tag] to [param target] (null = entity-wide, a [SkillNode] =
## node-scoped). Refcounted on the carrier ([method SkillNode.add_tag] /
## [method Entity.add_tag]) — granting the same tag twice and revoking once
## leaves it active, because a second source is still relying on it. Ledgered
## alongside modifier grants (same [EffectInstance]), so [method revoke_all]
## sweeps both channels in one pass. Returns the token [method revoke] takes back.
func grant_tag(tag: StringName, target: Variant = null) -> Variant:
	if entity == null:
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


func _detach(handle: StatModifier, target: Variant) -> void:
	if target == null:
		if entity != null and entity.stat_board != null:
			entity.stat_board.remove_modifier(handle)
		return
	# Untyped read before validity check — a typed assignment of a freed
	# instance crashes first. See .claude/rules/godot-workflow.md.
	if not is_instance_valid(target):
		return
	var node: SkillNode = target
	node.remove_local_modifier(handle)


## Apply [param delta] (±1) to [param tag]'s refcount on [param target] (null =
## entity-wide). Returns false (and does nothing) if the target is gone —
## mirrors [method _detach]'s freed-node guard, since a cascade can free a node
## between grant and revoke.
func _apply_tag(target: Variant, tag: StringName, delta: int) -> bool:
	if target == null:
		if entity == null:
			return false
		if delta > 0:
			entity.add_tag(tag)
		else:
			entity.remove_tag(tag)
		return true
	if not is_instance_valid(target):
		return false
	var node: SkillNode = target
	if delta > 0:
		node.add_tag(tag)
	else:
		node.remove_tag(tag)
	return true
