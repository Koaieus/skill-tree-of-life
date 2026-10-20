@tool
class_name FluxEffect
extends SpellOnHitEffect

## Copies [member share] of the landed node's row of [member def] out through
## [member StatusDef.spread]'s own rule, as if the node had died
## ([method StatusSpread.copy_out]) — the node keeps every stack. Only a status
## with a spill copies anything.
##
## The receivers are the rule's neighbours of the node on the world the walk
## reads; each gets one status hit whose stacks are decided at LAND, on the
## authority's shadow, from the node's row as the earlier hits of this
## landing left it: the intake riders (placed first, ADR 0067) and any effect
## authored before it. The
## hit is then [member StatusInstance.power_resolved]: the record ships plain
## status hits and a replay lands the same numbers.

@export var def: StatusDef = null
## Fraction of the node's row handed to the rule, which splits it over its
## receivers. Tentative.
@export_range(0, 1) var share: float = 0.5


func _apply_spell(lctx: LandingContext) -> void:
	var node: SkillNode = lctx.target if lctx.target != null else lctx.node
	if def == null or def.spread == null or node == null or lctx.cast == null:
		return
	var world := lctx.cast.world
	var nodes: Array[SkillNode] = [node]
	var field := StackField.over_world(def, def.spread.ownership_mask, world, nodes, lctx.cast.graph)
	for m in field.masked_neighbours(world.combat_for(node)):
		var hit := _FluxCopy.new()
		MultiplyRowEffect.stamp(hit, def, lctx)
		hit.target = m.real()
		hit.origin = node
		hit.fluxed = node
		hit.graph = lctx.cast.graph
		hit.share = share
		lctx.hits.append(hit)


func status_def() -> StatusDef:
	return def


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	var what := def.display_name if def != null and def.display_name != "" else "status"
	return "Copies %s%% of the node's %s out as if it died; the node keeps it." \
			% [NumFmt.num(share * 100.0), what]


## One receiver's copy: its amount is what the rule hands [member HitInstance.target]
## from [member fluxed]'s row at the moment this lands.
class _FluxCopy extends StatusInstance:
	var fluxed: SkillNode = null
	var graph: Graph = null
	var share: float = 0.5

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		if not power_resolved:
			power = 0.0
			var key: Variant = def.group_key(_attacker_camp_id(), _attacker_id()) if def != null else null
			if key != null and def.spread != null and fluxed != null and world != null:
				var nodes: Array[SkillNode] = [fluxed]
				var field := StackField.over_world(def, def.spread.ownership_mask, world, nodes, graph, key)
				for t in def.spread.copy_out(field, world.combat_for(fluxed), share):
					if t != null and t.to == node:
						power += t.amount
			power_resolved = true
		super.land_on(node, world)
