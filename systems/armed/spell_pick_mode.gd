class_name SpellPickMode
extends ArmedMode

## Stub.

var magic: MagicMode


func _init(p_magic: MagicMode) -> void:
	magic = p_magic
	ctl = p_magic.ctl


func pick(_spell: SpellDef) -> void:
	pass
