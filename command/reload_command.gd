class_name ReloadCommand
extends Command

## "Reload the quiver." Costs 1 AP; yield = Σ over the entity's turn-start
## leaf set ∪ core of the node-local `arrows_per_reload`, plus each special
## type's flat `<type>_arrows_per_reload`, clamped by [Quiver] capacity.
##
## Stub (#496 swarmify, 2026-09-18): NOT yet registered in [CommandCodec] —
## the child issue registers the tag when it lands `apply`.

const TAG: StringName = &"reload"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> ReloadCommand:
	return ReloadCommand.new(int(d.get("entity_id", 0)))
