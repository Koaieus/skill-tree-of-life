@tool
class_name ConceptCard
extends PanelContainer

## The hover card that explains an identity as a concept: an [IdentityBadge]
## and the noun in the identity's hue, the Summary, then one
## [SpellTooltipSection] per further [StatusSections] entry. Only ASPECT
## identities with a status have a card ([method supports]); the derivation
## lives in [StatusSections], this scene only renders it.
##
## `@tool` with a rebinding [member identity] export: open the scene, pick an
## identity, and the card previews in the editor.

const _SECTION := preload("res://ui/spell_tooltip/spell_tooltip_section.tscn")

## The concept shown; setting it rebinds.
@export var identity: Identity:
	set(v):
		identity = v
		_refresh()

## Wrap width of the card in px. Tentative, easy to change.
@export_range(160, 640) var max_width: int = 320:
	set(v):
		max_width = v
		_refresh()

## Tier the noun's hue is lifted through ([method Emissive.at]).
@export var noun_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(v):
		noun_tier = v
		_refresh()

@onready var _badge: IdentityBadge = %Badge
@onready var _noun: Label = %Noun
@onready var _summary: Label = %Summary
@onready var _sections: VBoxContainer = %Sections


## Whether [param of] has a concept card: an Aspect identity whose aspect
## carries a status. Aspect ids are identity ids.
static func supports(of: Identity) -> bool:
	return _status_of(of) != null


static func _status_of(of: Identity) -> StatusDef:
	if of == null or of.kind != Identity.Kind.ASPECT:
		return null
	var aspect := AspectRoster.shared().by_id(of.id)
	return aspect.status if aspect != null else null


func _ready() -> void:
	_refresh()


## Show [param of]'s card; an unsupported identity shows the header only.
func bind(of: Identity) -> void:
	identity = of


## The rendered Summary text.
func summary_text() -> String:
	return _summary.text if _summary != null else ""


func _refresh() -> void:
	if not is_node_ready():
		return
	custom_minimum_size.x = max_width
	_badge.identity = identity
	_noun.text = identity.noun if identity != null else ""
	if identity != null:
		_noun.add_theme_color_override(&"font_color", Emissive.at(identity.tint, Emissive.stops(noun_tier)))
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	_summary.text = ""
	for section: Dictionary in StatusSections.build(_status_of(identity)):
		var lines: SpellSections.Lines = section.lines
		if section.title == StatusSections.SUMMARY:
			_summary.text = "\n".join(lines.lines)
			continue
		var view: SpellTooltipSection = _SECTION.instantiate()
		_sections.add_child(view)
		view.header_text = section.title
		view.bind(lines.lines, lines.dynamic)
	_summary.visible = not _summary.text.is_empty()
	size = Vector2(max_width, 0.0)
