@tool
class_name HealAuraEffect
extends AuraEffect

## The D-10 healing channel, ported onto [AuraEffect] (#720, replacing the
## standalone [code]CoreAura[/code]/[code]HealAura[/code] pair): heals through
## combat (ignores the D-9 damage gate, [method SkillNode.apply_turn_regen])
## and grants no ramp — a flat top-up applied alongside, never through, that
## method's [code]node_healing[/code] / [code]regen_stacks[/code] term.
##
## [b]A payload-channel subclass, per the [AuraEffect] docstring's
## [method _has_payload] / [method _grant_to] split.[/b] [TagAuraEffect] is
## that split on the tag channel; this is the same split on a per-turn
## channel — the heal is not a membership grant, so it lands from an
## overridden [method _on_turn_start] instead. Everything else (the three
## knobs, the origin rule, batching, the #626 incremental
## [method AuraEffect._topology_changed] paths) is inherited unchanged, and
## stays harmless for this channel because [method _grant_to] never grants
## anything — an alloc/dealloc between turns walks and no-ops, it does not
## double-heal.
##
## [b]Clamped at 0 regardless of [member AuraEffect.discard].[/b] A negative
## heal at turn start would be damage with no [AttackRecord] behind it (see
## `.claude/rules/attack-timeline.md`), so the floor is an explicit `maxf`
## here, never `discard`'s job — `discard` only ever decided whether a
## MODIFIER-channel value was worth granting.
##
## [b]Integer, floored once at the read (ADR 0017).[/b] Health is an INT
## quantity end to end; a computed `6.667` heals `6`, not a fraction carried
## forward. The floor happens exactly once, after the clamp, right where
## [method DistanceScale.scale] is read — never again downstream.

## Magnitude at distance 0 — the leaf value [member AuraEffect.distance_scale]
## shapes. Lives on the resource, not the board (D-10 /
## `.claude/rules/stats-system.md` "Aura parameters live on the resource").
@export var base: float = 0.0


## Anything to radiate? This channel carries no [member modifiers], so the
## base [Effect]'s emptiness check would always read false — a bare [member
## base] or an authored [member AuraEffect.distance_scale] both count as
## "configured".
func _has_payload() -> bool:
	return base > 0.0 or distance_scale != null


## No-op. This channel's payload lands from [method _on_turn_start], never
## from a membership grant — the inherited [method AuraEffect.recompute] /
## [method AuraEffect._topology_changed] paths call this on every grant and
## every alloc/dealloc regardless, so it must do nothing, not "nothing
## configured".
func _grant_to(_ctx: EffectContext, _node: SkillNode, _distance: float, _bound: float) -> void:
	pass


## D-10: heal every node in reach, once per turn, outside the D-9 regen gate.
## Reuses the inherited walk ([method AuraEffect._distances] / [method
## AuraEffect._bound] / the origin rule) so [member AuraEffect.reach] /
## [member AuraEffect.metric] / [member AuraEffect.distance_scale] /
## [member AuraEffect.scope] are the same knobs every other aura authors.
func _on_turn_start(ctx: EffectContext) -> void:
	if not _has_payload():
		return
	var source := ctx.source_node if ctx.source_node != null else ctx.core_location
	var mirror := _mirror(ctx)
	if source == null or mirror == null:
		return
	var dists := _distances(source, mirror)
	var bound := _bound(dists)
	for node in dists:
		if not is_instance_valid(node):
			continue
		var d: float = dists[node]
		var computed: float = base if distance_scale == null else distance_scale.scale(d, bound, base)
		# Clamped here, not via `discard` (see class doc): a negative result
		# heals 0, it never damages. Floored once, here, per ADR 0017 —
		# health is an INT quantity end to end.
		node.heal_damage(floorf(maxf(computed, 0.0)), self)


func get_description() -> String:
	if not description.is_empty():
		return description
	var body := "Heals %s HP" % base
	if distance_scale != null and not distance_scale.phrase.is_empty():
		return "%s, %s" % [body, distance_scale.phrase]
	return body
