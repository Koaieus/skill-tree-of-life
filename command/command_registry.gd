class_name CommandRegistry
extends RefCounted

## STUB — the shape #999's red test parses against; the body follows.


static func has(_tag: StringName) -> bool:
	return false


static func tags() -> Array[StringName]:
	return []


static func decode(_d: Dictionary) -> Command:
	return null


static func handler_for_tag(_tag: StringName) -> CommandHandler:
	return null


static func handler_for(command: Command) -> CommandHandler:
	return handler_for_tag(command.type_tag())
