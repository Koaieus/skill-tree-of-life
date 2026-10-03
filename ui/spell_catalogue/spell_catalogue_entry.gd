@tool
class_name SpellCatalogueEntry
extends PanelContainer

## One spell's long-form card in the spell catalogue (#853): icon, name,
## tagline, the four derived sections, then the authored [member
## SpellDef.description] verbatim.
##
## [b]Read-only, no caster.[/b] The four sections are the SAME
## [SpellTooltipSection] scene the hover tooltip instances, bound from the same
## [method SpellSections.build] — called here with no board, so every number is
## the spell's printed base and nothing wears the gold accent. This script
## derives nothing about a spell; it only places what [SpellSections] says.
##
## Its own scene, instanced once per spell by [SpellCatalogueList] — never a
## code-built tree of `Label.new()`s (`.claude/rules/scene-composition.md`).

## The spell this card shows, or null before [method bind].
var spell: SpellDef = null

@onready var _icon: TextureRect = %Icon
@onready var _header: PanelHeader = %Header
@onready var _tagline_label: Label = %TaglineLabel
@onready var _cast_section: SpellTooltipSection = %CastSection
@onready var _on_arrival_section: SpellTooltipSection = %OnArrivalSection
@onready var _then_section: SpellTooltipSection = %ThenSection
@onready var _crits_section: SpellTooltipSection = %CritsSection
@onready var _description_label: Label = %DescriptionLabel


## Fill every field from [param def]. Safe before `_ready` — the fill is
## deferred until the scene's children exist.
func bind(def: SpellDef) -> void:
	spell = def
	if not is_node_ready():
		await ready
	_refresh()


func _refresh() -> void:
	if spell == null:
		return
	_icon.texture = spell.icon
	_icon.visible = spell.icon != null
	_header.bind(spell.name, "Requires degree ≥ %d" % spell.min_degree)
	_tagline_label.text = spell.tagline
	_tagline_label.visible = spell.tagline != ""
	_description_label.text = spell.description
	_description_label.visible = spell.description != ""

	var sections := SpellSections.build(spell, null)
	_cast_section.bind(sections.cast.lines, sections.cast.dynamic)
	_on_arrival_section.bind(sections.on_arrival.lines, sections.on_arrival.dynamic)
	_then_section.bind(sections.then.lines, sections.then.dynamic)
	_crits_section.bind(sections.crits.lines, sections.crits.dynamic)


# --- read-back, for tests and for anything that greps a card ------------------

func header_text() -> String:
	return _header.header


func tagline_text() -> String:
	return _tagline_label.text


func description_text() -> String:
	return _description_label.text
