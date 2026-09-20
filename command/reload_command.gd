class_name ReloadCommand
extends Command

## "Reload the quiver." Costs 1 AP; yield = Σ over the entity's turn-start
## leaf set ∪ core of the node-local `arrows_per_reload`, plus each special
## type's flat `<type>_arrows_per_reload`, clamped by [Quiver] capacity.
## Registered in [CommandCodec]; [CommandApplier] gates it on the actor's turn
## + 1 AP and applies it through [method Entity.reload].

const TAG: StringName = &"reload"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> ReloadCommand:
	return WireFields.from_dict(ReloadCommand, d)
