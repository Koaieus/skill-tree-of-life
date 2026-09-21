class_name RevealInstance
extends HitInstance

## A scout arrow's landing (#1033): no HP, no status — [member amount] is a
## vision RADIUS in world units, [member attacker] the firer whose vision group
## gains it, [member target] the node it lands on. No gate: it reveals wherever
## it lands, allocated or not, any owner.
##
## Live-only on purpose: a shadow world is a preview or the authority's own
## resolve, and the reveal is a [VisionSystem] fact, not combat state a slice
## could hold — so a shadow land is a no-op (the preview shows no disc) and the
## live land emits [signal Events.node_scouted] once. A peer hears the same
## emit from its own rebuilt [AttackRecord] (`.claude/rules/attack-timeline.md`).
## The record needs nothing beyond `kinds/amounts/attackers/targets`.


func _init() -> void:
	kind = Kind.REVEAL


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	# The radius is what "landed" — stamped on every world, because the
	# authority resolves on a shadow and [method AttackRecord.capture] ships
	# `effective_amount`, never `amount`.
	effective_amount = amount
	if world.is_shadow():
		return
	Events.node_scouted.emit(node.host, attacker, amount)


func _to_string() -> String:
	return "RevealInstance(r=%.0f on %s)" % [amount, target.name if target != null else "null"]
