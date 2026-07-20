class_name EffectInstance
extends RefCounted

## One live attachment of an [Effect] to an [Entity]. Created by
## [method Entity.grant_effect]; discarded by [method Entity.revoke_effect].
##
## Holds the **grant ledger**: the exact [StatModifier] instances this effect
## put onto a board, paired with the target they landed on. Revocation is by
## object identity — [StatModifier] carries no source/provenance field (see
## [ModifierBinding], deliberately dormant), so retaining the handle IS the
## provenance. Same pattern [Keystone.apply] already used by returning its
## installed array.
##
## The ledger lives here, per grant, and never on the [Effect] resource — a
## single `.tres` is shared across every entity that references it. Runtime
## state on the resource would have entities silently clobbering each other.

var effect: Effect
## The node that granted this effect, if any (keystone / addon carrier). Null
## for entity-wide effects (core class). Also the key used to revoke a node's
## effects when it is deallocated.
var source_node: SkillNode
## Built once by [method Entity.grant_effect] and reused for every dispatch, so
## a hook firing per node in a cascade doesn't allocate a context each time.
var context: EffectContext

## Opaque per-grant token for a tag row, returned by [method record_tag] and
## handed back to [method EffectContext.revoke]. [RefCounted] rather than the
## tag [StringName] itself (or a Dictionary) so identity — not value — is what
## [method forget] matches on: two effects granting the same tag to the same
## target is legal (refcounted), and a value-equal handle would let revoking
## one collapse onto the other's row.
class TagToken extends RefCounted:
	var tag: StringName
	var target: Variant

## Grant ledger: `[{ kind: &"modifier"|&"tag", handle: Variant, target: Variant,
## tag: StringName (tag rows only) }]`, where `target` is null (the entity
## board / entity-wide tags) or a [SkillNode] (its `node_board` / its tag set).
## Both channels share one list so [method EffectContext.revoke_all] sweeps
## them in a single pass — no separate "did I forget the tag ledger" bookkeeping
## at any call site.
var _grants: Array[Dictionary] = []


func record(handle: StatModifier, target: Variant) -> void:
	_grants.append({&"kind": &"modifier", &"handle": handle, &"target": target})


## Records a tag grant and returns its token — the [TagToken] identity
## [method forget] matches on, and what [method EffectContext.revoke] takes back.
func record_tag(tag: StringName, target: Variant) -> TagToken:
	var token := TagToken.new()
	token.tag = tag
	token.target = target
	_grants.append({&"kind": &"tag", &"handle": token, &"target": target, &"tag": tag})
	return token


## [param handle] is a [StatModifier] (modifier row) or a [TagToken] (tag row) —
## whichever [method record] / [method record_tag] handed back.
func forget(handle: Variant) -> Dictionary:
	for i in _grants.size():
		if _grants[i][&"handle"] == handle:
			return _grants.pop_at(i)
	return {}


## Every grant matching [param target] (pass the sentinel `false` to mean "any
## target"). Returns the ledger rows, newest last.
func grants(target: Variant = false) -> Array[Dictionary]:
	if typeof(target) == TYPE_BOOL and target == false:
		return _grants.duplicate()
	var out: Array[Dictionary] = []
	for g in _grants:
		if g[&"target"] == target:
			out.append(g)
	return out


## Modifier handles currently granted to [param target]. The read an aura uses
## to diff its buffed set — it keeps no dict of its own. Tag rows are excluded
## (their handle isn't a [StatModifier]); use [method grants] for a kind-mixed read.
func handles_for(target: Variant) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for g in grants(target):
		if g.get(&"kind", &"modifier") == &"modifier":
			out.append(g[&"handle"])
	return out


## Distinct non-null [SkillNode] targets currently holding a grant. Freed nodes
## are skipped: a cascade or death can free a node before the next recompute.
func node_targets() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for g in _grants:
		var t: Variant = g[&"target"]
		# Untyped read first — a typed assignment of a freed instance crashes
		# before is_instance_valid can run. See .claude/rules/godot-workflow.md.
		if t == null or not is_instance_valid(t):
			continue
		if t is SkillNode and not out.has(t):
			out.append(t)
	return out
