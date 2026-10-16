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
## [b]Whole HP, rounded once by the heal door (ADR 0033).[/b] This effect hands
## the clamped raw amount to [method SkillNode.heal_damage]; the door applies
## `healing_received` and rounds up to whole HP. A computed `6.667` heals `7`.
##
## [b]Readout.[/b] [method readout_payloads] answers the tooltip's "+N HP/turn"
## through the same [method _heal_frame] / [method amount_at] pair
## [method _on_turn_start] uses, so the scaled, clamped math is never mirrored.

## Magnitude at distance 0 — the leaf value [member AuraEffect.distance_scale]
## shapes. Lives on the resource, not the board (D-10 /
## `.claude/rules/stats-system.md` "Aura parameters live on the resource").
@export var base: float = 0.0

## D-10 sub-linear scaling (#896): the flat [member base] plus this times
## [code]sqrt(CON)[/code] is the value handed to [member
## AuraEffect.distance_scale] — CON read LIVE off [code]ctx.entity.stat_board[/code]
## every [method _on_turn_start], never cached on the resource, so a
## mid-run CON grant raises next turn's heal (a board stat read as a formula
## input — `.claude/rules/stat-knobs-and-bins.md`). Sub-linear on purpose
## (D-10, `docs/adr/legacy-mvp-decisions.md`): node_health grows ~linearly with
## CON, so a flat aura decays into irrelevance as levels climb, but matching
## that growth 1:1 would keep the fortress dominant forever — `sqrt` sits
## between the two. `max_hops` (on [member AuraEffect.reach]) deliberately
## does NOT scale with either term; only the payload does.
@export var con_coefficient: float = 0.0


## Anything to radiate? This channel carries no [member modifiers], so the
## base [Effect]'s emptiness check would always read false — a bare [member
## base], a nonzero [member con_coefficient], or an authored [member
## AuraEffect.distance_scale] all count as "configured".
func _has_payload() -> bool:
	return base > 0.0 or con_coefficient > 0.0 or distance_scale != null


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
	var frame := _heal_frame(ctx)
	if frame.is_empty():
		return
	var source: SkillNode = frame.source
	var dists: Dictionary[SkillNode, float] = frame.dists
	for node in dists:
		if not is_instance_valid(node):
			continue
		# The door's `source` is a HitInstance or null. The aura rides
		# as `HitInstance.source` (the thing that produced the hit), so nothing
		# downstream loses the "who" — and `effective_amount` comes back.
		var heal := HealInstance.new()
		heal.amount = amount_at(dists[node], frame.bound, frame.magnitude)
		heal.source = self
		heal.attacker = ctx.entity
		heal.target = node
		heal.origin = source
		node.heal_damage(heal.amount, heal)


## The per-turn heal [param node] would receive from this aura, as one
## [NodeEffectReadout] payload row in whole HP — what the heal door lands
## before the HP cap clips it. No row when that is 0 or the node is out of
## reach. Side-effect free: reads the warm distance cache, heals nothing.
func readout_payloads(node: SkillNode, instance: EffectInstance) -> Array[NodeEffectReadout]:
	var out: Array[NodeEffectReadout] = []
	if node == null or instance == null or instance.context == null:
		return out
	var frame := _heal_frame(instance.context)
	if frame.is_empty() or not (frame.dists as Dictionary).has(node):
		return out
	var raw := amount_at(frame.dists[node], frame.bound, frame.magnitude)
	# The door's two steps (NodeCombat.heal_damage): `healing_received`, then
	# whole HP. A negative product is Wither damage, not a heal row.
	var landed := HitPoints.whole(raw * float(node.get_local_value(&"healing_received")))
	if landed <= 0.0:
		return out
	var row := NodeEffectReadout.new()
	row.payload_amount = landed
	row.payload_unit = "HP/turn"
	out.append(row)
	return out


## The pre-door heal at [param distance]: [member AuraEffect.distance_scale]
## over [param magnitude], clamped at 0 here, never via `discard` (see class
## doc) — a negative result heals 0, it never damages. The ONE home of this
## math; the heal door does the rounding.
func amount_at(distance: float, bound: float, magnitude: float) -> float:
	var computed: float = magnitude if distance_scale == null else distance_scale.scale(distance, bound, magnitude)
	return maxf(computed, 0.0)


## Everything per-source a heal pass needs, shared by [method _on_turn_start]
## and [method readout_payloads]: `source`, `dists`, `bound`, `magnitude`.
## Empty when there is nothing to radiate or nowhere to radiate from.
func _heal_frame(ctx: EffectContext) -> Dictionary:
	if not _has_payload():
		return {}
	var source := ctx.source_node if ctx.source_node != null else ctx.core_location
	var mirror := _mirror(ctx)
	if source == null or mirror == null:
		return {}
	var dists := _heal_distances(source, mirror)
	# CON read live, once per pass (not cached on the resource, not per-node —
	# every node this walk touches shares the same source CON). `entity` can
	# be null off a shadow slice with no live entity behind it; treat that the
	# same as CON 0, matching `con_coefficient 0`'s no-op.
	var con: float = 0.0
	if ctx.entity != null and ctx.entity.stat_board != null:
		var raw: Variant = ctx.entity.stat_board.get_value(&"constitution")
		if raw != null:
			con = float(raw)
	return {
		"source": source,
		"dists": dists,
		"bound": _bound(dists),
		"magnitude": base + con_coefficient * sqrt(con),
	}


## [method AuraEffect._distances], but through the shared [AuraDistanceCache]
## when it can be: a plain hop reach with no metric is exactly
## [method HopMetric.depths]' ball, so the turn-start pass warms the cache and
## a tooltip hover between topology changes walks nothing. The cache may hold
## a WIDER same-generation ball (another aura asked further), hence the filter.
func _heal_distances(source: SkillNode, mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	if metric != null or not (reach is HopRangeFinder):
		return _distances(source, mirror)
	var hops := (reach as HopRangeFinder).max_hops
	var out: Dictionary[SkillNode, float] = {}
	var ball := HopMetric.depths(source, mirror, hops)
	for n in ball:
		if ball[n] <= hops:
			out[n] = ball[n]
	return out


func get_description() -> String:
	if not description.is_empty():
		return description
	var body := "Heals %s HP" % base
	if distance_scale != null and not distance_scale.phrase.is_empty():
		return "%s, %s" % [body, distance_scale.phrase]
	return body
