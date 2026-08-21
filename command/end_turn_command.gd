class_name EndTurnCommand
extends Command

## "I am done." The only command with no target at all — the actor IS the
## payload. [TurnManager] on the host is the clock, so this is what stops
## `_tick_until_ready`'s group-order tiebreak from being a sync hazard.

const TAG: StringName = &"end_turn"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> EndTurnCommand:
	return EndTurnCommand.new(int(d.get("entity_id", 0)))
