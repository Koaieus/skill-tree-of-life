class_name CommandRegistry
extends RefCounted

## The one table of verbs (#999): `TAG -> {from_dict, handler}`. [CommandCodec]
## reads the first half to rebuild a command off the wire; [CommandApplier]
## reads the second to gate and apply it. A new verb is ONE line in
## [method _build] — and `test/unit/command/test_command_registry.gd` fails
## for any `command/*_command.gd` that forgot it.
##
## Why this is not a static table on [Command]: `AllocateCommand extends
## Command` while `Command` names `AllocateCommand` is a parse-time cycle in
## GDScript (see [CommandCodec]'s note). A registry outside the inheritance
## chain has no cycle.
##
## Handlers are shared and stateless — one instance per verb for the process
## lifetime; everything per-command arrives through the command and the
## [CommandContext].


class Entry:
	extends RefCounted
	var from_dict: Callable
	var handler: CommandHandler

	func _init(from_dict_: Callable, handler_: CommandHandler) -> void:
		from_dict = from_dict_
		handler = handler_


static var _entries: Dictionary[StringName, Entry] = {}


static func _register(tag: StringName, from_dict: Callable, handler: CommandHandler) -> void:
	assert(not _entries.has(tag), "CommandRegistry: duplicate tag '%s'" % tag)
	_entries[tag] = Entry.new(from_dict, handler)


static func _build() -> void:
	_register(AllocateCommand.TAG, AllocateCommand.from_dict, AllocateCommandHandler.new())
	_register(DeallocateCommand.TAG, DeallocateCommand.from_dict, DeallocateCommandHandler.new())
	_register(DeallocateSetCommand.TAG, DeallocateSetCommand.from_dict,
			DeallocateSetCommandHandler.new())
	_register(MassAllocateCommand.TAG, MassAllocateCommand.from_dict,
			MassAllocateCommandHandler.new())
	_register(StakeCommand.TAG, StakeCommand.from_dict, StakeCommandHandler.new())
	_register(ReloadCommand.TAG, ReloadCommand.from_dict, ReloadCommandHandler.new())
	_register(ExtractCommand.TAG, ExtractCommand.from_dict, ExtractCommandHandler.new())
	_register(MoveCoreCommand.TAG, MoveCoreCommand.from_dict, MoveCoreCommandHandler.new())
	_register(EndTurnCommand.TAG, EndTurnCommand.from_dict, EndTurnCommandHandler.new())
	_register(StartTurnCommand.TAG, StartTurnCommand.from_dict, StartTurnCommandHandler.new())
	_register(PickLootCommand.TAG, PickLootCommand.from_dict, PickLootCommandHandler.new())
	_register(LootRoundCommand.TAG, LootRoundCommand.from_dict, LootRoundCommandHandler.new())
	_register(ToggleTempUpgradeCommand.TAG, ToggleTempUpgradeCommand.from_dict,
			ToggleTempUpgradeCommandHandler.new())
	_register(LaunchAttackCommand.TAG, LaunchAttackCommand.from_dict,
			LaunchAttackCommandHandler.new())


static func _entry(tag: StringName) -> Entry:
	if _entries.is_empty():
		_build()
	return _entries.get(tag)


static func has(tag: StringName) -> bool:
	return _entry(tag) != null


static func tags() -> Array[StringName]:
	_entry(&"")
	var out: Array[StringName] = []
	out.assign(_entries.keys())
	return out


## Rebuild a command from its wire form, or null on an unknown/missing tag.
## [member Command.intent_id] is NOT restored here — that is [CommandCodec]'s
## job, once, at the decode seam.
static func decode(d: Dictionary) -> Command:
	var entry := _entry(StringName(d.get("type", &"")))
	if entry == null:
		return null
	return entry.from_dict.call(d)


static func handler_for_tag(tag: StringName) -> CommandHandler:
	var entry := _entry(tag)
	return entry.handler if entry != null else null


static func handler_for(command: Command) -> CommandHandler:
	return handler_for_tag(command.type_tag())
