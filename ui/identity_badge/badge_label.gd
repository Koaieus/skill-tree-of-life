class_name BadgeLabel
extends RichTextLabel

## The prose label with hoverable concepts: [member badge_text] is authored
## [BadgeText] (`{id}` / `{id:amount}` tokens), and hovering a token whose
## identity has a [ConceptCard] shows that card as the native tooltip (themed by
## the engine's `TooltipPanel`). Every other hint falls back to the engine's
## default tooltip.

const _CARD := preload("res://ui/concept_card/concept_card.tscn")

## Authored text with [BadgeText] tokens; setting it re-renders.
@export_multiline var badge_text: String = "":
	set(v):
		badge_text = v
		if is_node_ready():
			BadgeText.render(self, badge_text)


func _ready() -> void:
	BadgeText.render(self, badge_text)


## The shown text as plain prose ([method BadgeText.strip]).
func plain_text() -> String:
	return BadgeText.strip(badge_text)


func _make_custom_tooltip(for_text: String) -> Object:
	var identity := BadgeText.concept_of(for_text)
	if identity == null:
		return null
	var card: ConceptCard = _CARD.instantiate()
	card.bind(identity)
	return card
