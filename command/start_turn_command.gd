class_name StartTurnCommand
extends Command

## "The clock opens on this entity." The run's FIRST turn, as a command — the
## bookend to [EndTurnCommand], and it exists for the same reason (#756).
##
## [EndTurnCommand]'s note says the handoff is command-ordered so
## `_tick_until_ready`'s group-order tiebreak runs at the same point of the
## command stream on every peer. That guarantee is only worth anything if every
## peer STARTS from the same cursor, and until this command existed no peer did:
## [method GameRoot._ready]'s `auto_start_turn` block called
## [method TurnManager.start_turn] on THIS machine's seated hero, so the host
## opened on its Player 1 and the client opened on its Player 2. From there
## every mirrored [EndTurnCommand] re-ran `_tick_until_ready` from a different
## starting cursor, and turn-start upkeep — pool replenish, node regen, the
## class aura — ran for the wrong entity on the wrong turn. Ownership and
## topology stayed identical (the mirror allocates exactly the nodes it is
## told to); the ACCUMULATED tier drifted, which is precisely what #756
## measured.
##
## So the opening cursor is RECEIVED, never decided locally — the same split
## `.claude/rules/multiplayer-sync.md` draws for every other host decision. The
## mirror's other door onto the cursor is the resync, which carries it too; see
## [method EntitySnapshot.restore_turn_cursor].
##
## No node payload: like [EndTurnCommand], the actor IS the message.

const TAG: StringName = &"start_turn"


func type_tag() -> StringName:
	return TAG


static func from_dict(d: Dictionary) -> StartTurnCommand:
	return StartTurnCommand.new(int(d.get("entity_id", 0)))
