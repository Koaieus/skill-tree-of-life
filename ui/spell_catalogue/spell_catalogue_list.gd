@tool
class_name SpellCatalogueList
extends ScrollContainer

## The scrolling column of [SpellCatalogueEntry] cards that IS the spell
## catalogue (#853), shared by both of its doors: the in-run modal body
## ([SpellCatalogueBody]) and the frontmatter panel ([SpellCataloguePanel])
## each instance this one scene, so there is one list and two frames — never
## two lists. Whoever hosts it decides its size (a modal body pins a
## `custom_minimum_size`, a frontmatter panel lets it fill the column); this
## scene decides only what is in it.
##
## Lists [constant SpellCatalog.ALL] — every authored spell, in catalogue order
## — not any entity's [SpellBook]: the spellbook is "what I know", the
## catalogue is "what exists" (owner, 2026-09-10).

const _ENTRY := preload("res://ui/spell_catalogue/spell_catalogue_entry.tscn")

@onready var _entries: VBoxContainer = %Entries


## Rebuild the list for [param defs] (the whole catalogue by default). One
## [SpellCatalogueEntry] instance per def, in the order given.
func populate(defs: Array[SpellDef] = SpellCatalog.ALL) -> void:
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	for def in defs:
		if def == null:
			continue
		var entry: SpellCatalogueEntry = _ENTRY.instantiate()
		_entries.add_child(entry)
		entry.bind(def)


## The cards currently shown, top to bottom.
func entries() -> Array[SpellCatalogueEntry]:
	var out: Array[SpellCatalogueEntry] = []
	for child in _entries.get_children():
		var entry := child as SpellCatalogueEntry
		if entry != null and not entry.is_queued_for_deletion():
			out.append(entry)
	return out
