@tool
class_name SelfCorruptEffect
extends Effect

## The bargain half of an addon that pays in its own carrier: at each of the
## holder's turn starts, [member stacks_per_turn] of [member def] land on the
## node that carries this effect ([member EffectContext.source_node]).
##
## It goes through the row's normal door — [method NodeCombat.apply_status],
## so the def's `reapply` and the carrier's resistance gate apply — never a
## raw power write, and the attacker's `*_stacks_per_hit` is not folded: the
## number is this knob. Granted per allocation and revoked by source node, so
## cutting the carrier stops the growth. Fires only for the entity it is
## granted to.

## The status the carrier grows on itself.
@export var def: StatusDef = null
## Stacks landed on the carrier per holder turn start.
@export_range(1, 10, 1) var stacks_per_turn: int = 1


func _on_turn_start(_ctx: EffectContext) -> void:
	pass


func get_description() -> String:
	if not description.is_empty():
		return description
	var noun: String = def.display_name if def != null else "status"
	return "Each turn, this node gains %d %s." % [stacks_per_turn, noun]
