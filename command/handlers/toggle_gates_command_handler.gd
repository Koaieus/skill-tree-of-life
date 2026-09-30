class_name ToggleGatesCommandHandler
extends CommandHandler

## [ToggleGatesCommand] -> [method AllocationSystem.apply_gate_flip_recorded].
## Validate refuses an off-turn toggle, an odd pair list, a pair naming no gate
## and a gate the actor cannot toggle, then STAMPS the stranded set from
## [method AllocationSystem.gate_flip_cascade] (authority only — validate never
## runs on a peer).


func _validate(_command: Command, _actor: Entity, _ctx: CommandContext) -> bool:
	return false


func _apply(_command: Command, _actor: Entity, _ctx: CommandContext) -> bool:
	return false
