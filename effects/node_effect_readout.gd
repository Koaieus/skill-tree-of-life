@tool
class_name NodeEffectReadout
extends RefCounted

## The READ side of the aura/effect machinery (#621) — as opposed to
## [EffectContext], which is the WRITE side an [Effect] uses to grant/revoke.
## One instance is one currently-granted leaf [StatModifier] landing on a
## specific [SkillNode] — or one non-modifier payload row (a per-turn heal,
## [method is_payload]) — plus enough provenance ([member effect],
## [member source_entity]) for a UI to say who put it there.
##
## [b]Walks every [Entity] in the graph[/b], not just the node's own owner —
## [AuraEffect.Scope.GLOBAL] and a hostile entity's aura reaching into someone
## else's territory are both legitimate, and [method SkillNode.ownership_bit]
## is exactly the vocabulary a consumer wants for "is this source mine, an
## ally's, or hostile" once it has [member source_entity].
##
## [b]One row per (effect, leaf) pair[/b] — a single aura may grant several
## leaf modifiers to the same node at once (a [CompositeStatModifier], e.g.
## Serpent's `aura_euclid_penalty` composite of blade/spell/ranged damage),
## and #621's own "aggregation is shown per source, not summed" decision means
## every leaf and every separate aura SOURCE stays its own entry all the way
## through to display. Hiding/rollup is a display-layer policy on top of this
## — see `ui/tooltip_fan/panels/effect_readout_panel.gd` — not this class's
## concern; this only answers "what is currently applied, and by whom".
##
## Reads back [method EffectInstance.handles_for] (the same ledger an aura's
## own [method AuraEffect.recompute] diffs against) rather than re-deriving
## "what's granted" by walking [SkillNode] internals — there is no public
## "every local modifier on this node" accessor, and this class doesn't need
## one: an effect's own ledger already answers "which of MY grants landed on
## this particular node".

var effect: Effect
var source_entity: Entity
## The granted leaf — null on a payload row (see [method is_payload]).
var modifier: StatModifier
## A payload row's per-node magnitude, already in the unit the node receives it
## (a heal is whole HP, as the heal door would land it). Only meaningful when
## [method is_payload].
var payload_amount: float = 0.0
## A payload row's display unit, e.g. `"HP/turn"`.
var payload_unit: String = ""


## The second row kind: a non-modifier payload answered by
## [method Effect.readout_payloads], not a ledger grant.
func is_payload() -> bool:
	return modifier == null


## Every currently-granted leaf modifier landing on [param node], across every
## [Entity] in [param graph]'s [member Graph.entities_container] — not just
## the node's own owner, followed by each effect's non-modifier payload rows
## ([method Effect.readout_payloads]). Empty (never null) when either argument
## is missing.
static func gather(node: SkillNode, graph: Graph) -> Array[NodeEffectReadout]:
	var out: Array[NodeEffectReadout] = []
	if node == null or graph == null or graph.entities_container == null:
		return out
	for c in graph.entities_container.get_children():
		if not (c is Entity):
			continue
		var entity := c as Entity
		for inst in entity.get_effects():
			for m in inst.handles_for(node):
				var row := NodeEffectReadout.new()
				row.effect = inst.effect
				row.source_entity = entity
				row.modifier = m
				out.append(row)
			for row in inst.effect.readout_payloads(node, inst):
				row.effect = inst.effect
				row.source_entity = entity
				out.append(row)
	return out
