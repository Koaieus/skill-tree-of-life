class_name CommandCodec
extends RefCounted

## The decode seam for [Command] deserialization. The tag -> type table itself
## is [CommandRegistry] (#999) — the same table the applier reads its handler
## from, so the two can never list different verbs.
##
## Why none of this is a static method on [Command]: `AllocateCommand extends
## Command` while `Command` names `AllocateCommand` is a parse-time cycle in
## GDScript. A registry outside the inheritance chain has no cycle, and the
## per-type `static from_dict` stays on each type where it belongs. If you see
## "Could not find type AllocateCommand" there, that is the cycle talking, not
## a stale class cache — do not reach for `mise run refresh`.
##
## Encoding is the other direction and needs no dispatch at all:
## `command.to_dict()`.


## Rebuild a command from its wire form. Returns null on an unknown or missing
## type tag (with a warning) rather than half-building something the applier
## would then act on.
## [b][member Command.intent_id] is restored HERE, not by each type's
## `from_dict`.[/b] It is a base-class field that every type carries and no type
## interprets, so one restore at the single decode seam beats twelve identical
## lines — and a new command type cannot forget it. Absent means 0, which is
## exactly what [method Command.to_dict]'s omit-when-zero rule produces.
static func from_dict(d: Dictionary) -> Command:
	var command := _build(d)
	if command != null:
		command.intent_id = int(d.get("intent_id", 0))
	return command


static func _build(d: Dictionary) -> Command:
	var command := CommandRegistry.decode(d)
	if command == null:
		push_warning("CommandCodec: unknown command type tag '%s'" % d.get("type", &""))
	return command
