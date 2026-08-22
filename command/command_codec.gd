class_name CommandCodec
extends RefCounted

## Tag -> concrete type dispatch for [Command] deserialization.
##
## Why this is not a static method on [Command]: `AllocateCommand extends
## Command` while `Command` names `AllocateCommand` is a parse-time cycle in
## GDScript. A codec outside the inheritance chain has no cycle, and the
## per-type `static from_dict` stays on each type where it belongs. If you see
## "Could not find type AllocateCommand" here, that is the cycle talking, not
## a stale class cache — do not reach for `mise run refresh`.
##
## Encoding is the other direction and needs no dispatch at all:
## `command.to_dict()`.


## Rebuild a command from its wire form. Returns null on an unknown or missing
## type tag (with a warning) rather than half-building something the applier
## would then act on.
static func from_dict(d: Dictionary) -> Command:
	var tag := StringName(d.get("type", &""))
	match tag:
		AllocateCommand.TAG:
			return AllocateCommand.from_dict(d)
		DeallocateCommand.TAG:
			return DeallocateCommand.from_dict(d)
		DeallocateSetCommand.TAG:
			return DeallocateSetCommand.from_dict(d)
		MassAllocateCommand.TAG:
			return MassAllocateCommand.from_dict(d)
		StakeCommand.TAG:
			return StakeCommand.from_dict(d)
		ExtractCommand.TAG:
			return ExtractCommand.from_dict(d)
		MoveCoreCommand.TAG:
			return MoveCoreCommand.from_dict(d)
		EndTurnCommand.TAG:
			return EndTurnCommand.from_dict(d)
		PickLootCommand.TAG:
			return PickLootCommand.from_dict(d)
		LootRoundCommand.TAG:
			return LootRoundCommand.from_dict(d)
		ToggleTempUpgradeCommand.TAG:
			return ToggleTempUpgradeCommand.from_dict(d)
		LaunchAttackCommand.TAG:
			return LaunchAttackCommand.from_dict(d)
	push_warning("CommandCodec: unknown command type tag '%s'" % tag)
	return null
