@tool
class_name SpellCataloguePanel
extends FrontmatterPanel

## The spell catalogue's frontmatter door (#853) — the meta menu's SPELL
## CATALOGUE leaf raises this on the `%PanelLayer`, exactly the way EXIT raises
## [ExitConfirmPanel]: a [FrontmatterPanel] inherited scene, registered by
## existing with its [member FrontmatterPanel.panel_id], never a modal-system
## modal (the frontmatter has no [HudRoot] and #573 keeps it that way).
##
## Its body is the same [SpellCatalogueList] the in-run modal frames — one
## list, two frames. Populated once at `_ready` (runtime only): the catalogue
## is static content, and a panel that fills itself needs nothing from the
## navigation state machine beyond being shown.

@onready var _list: SpellCatalogueList = %List


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		_list.populate()


func entries() -> Array[SpellCatalogueEntry]:
	return _list.entries()
