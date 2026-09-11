@tool
class_name SpellCatalogueBody
extends ModalBodyBase

## The spell catalogue's modal body (#853) — the in-run door, raised from the
## pause menu through [HudRoot]'s modal queue. Nothing to pick: it frames one
## [SpellCatalogueList] at a modal-sized minimum (the `%BodySlot` is a
## [CenterContainer], which hands a child exactly its minimum — see
## docs/domain/modal-system.md's layout gotcha) and reports the selection as
## always valid, so the base's Confirm button is simply CLOSE.

@onready var _list: SpellCatalogueList = %List


## The request is ignored — the catalogue is the same for everyone.
func populate(_request: Variant) -> void:
	_list.populate()
	selection_changed.emit()


func entries() -> Array[SpellCatalogueEntry]:
	return _list.entries()


func is_selection_valid() -> bool:
	return true


func status_text() -> String:
	return "%d spells" % _list.entries().size()


func confirm_text() -> String:
	return "CLOSE"
