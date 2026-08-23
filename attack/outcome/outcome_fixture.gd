class_name OutcomeFixture
extends Resource

## One recorded attack, on disk, replayable with no network and no live attack
## in the loop (#539).
##
## [b]The payload IS the wire form.[/b] [member command] is
## [method LaunchAttackCommand.to_dict] verbatim — `plan` + `record` + `seed` —
## so replaying a fixture exercises byte-for-byte the path a peer takes, and a
## change to that dictionary's shape breaks a committed fixture exactly as it
## would break a peer running an older build. That is the point: this is a
## regression surface for the replay path, not a demo.
##
## Which is also why fixtures are captured, never authored. Hand-writing an
## [AttackOutcome] is a much bigger tab (#534's fork 4) and a different claim —
## an authored outcome proves the applier applies what you typed, while a
## captured one proves the applier reproduces what the game did.
##
## [b]Both fingerprints, and why there are two.[/b] A replay is only meaningful
## against the pre-state it was captured on, so a fixture pins the world it
## went in on as well as the world it produced. A red
## [member world_fingerprint_at_capture] says *the board drifted* — re-capture
## the fixture; a red [member expected_fingerprint] with a green pre-state says
## *the replay path changed*, which is the failure worth waking up for.
##
## [b][member world_fingerprint_at_capture] is NOT #540's `pre_fingerprint`.[/b]
## Same idea, different lifetime and different owner. #540's is transient
## applier state stamped per command at `_drain` time and sent in
## [CommandLink]'s envelope; it is explicitly never serialized into
## `Command.to_dict()`, precisely so it cannot invalidate the fixtures this
## class commits. This field is authored once, at capture, and lives only here.

## [method LaunchAttackCommand.to_dict] — `type`, `entity_id`, `plan`, `record`,
## `seed`. Rebuilt with [method CommandCodec.from_dict], which is what a peer
## calls.
@export var command: Dictionary = {}

## [method WorldFingerprint.compute] of the world this was captured against,
## BEFORE the attack ran. The drift guard — see the class note.
@export var world_fingerprint_at_capture: int = 0

## [method WorldFingerprint.compute] after the replay lands. The assertion.
@export var expected_fingerprint: int = 0

## What this fixture is for, in one line, for whoever finds it red.
@export_multiline var notes: String = ""

## ISO date the capture was taken, so a stale fixture is visible as stale.
@export var captured_at: String = ""


## Rebuild the command. Returns null when the payload is empty or its tag is not
## a launch — a fixture that names something else is a mistake, not a variant.
func to_command() -> LaunchAttackCommand:
	if command.is_empty():
		return null
	return CommandCodec.from_dict(command) as LaunchAttackCommand


## The full wire trip, not just [method to_command]. `var_to_bytes` is what a
## transport actually does and it is the step that would reject a live Object,
## so a fixture that survives this holds none — the same proof
## `test_attack_record_replay.gd` runs on a freshly captured command, applied
## here to one that has been through `ResourceSaver` as well.
func to_command_over_the_wire() -> LaunchAttackCommand:
	if command.is_empty():
		return null
	var decoded: Variant = bytes_to_var(var_to_bytes(command))
	if not (decoded is Dictionary):
		return null
	return CommandCodec.from_dict(decoded as Dictionary) as LaunchAttackCommand


static func capture(source: LaunchAttackCommand, before: int, after: int,
		notes_: String = "") -> OutcomeFixture:
	var fixture := OutcomeFixture.new()
	fixture.command = source.to_dict()
	fixture.world_fingerprint_at_capture = before
	fixture.expected_fingerprint = after
	fixture.notes = notes_
	fixture.captured_at = Time.get_date_string_from_system()
	return fixture
