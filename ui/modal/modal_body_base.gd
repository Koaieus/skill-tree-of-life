@tool
class_name ModalBodyBase
extends HBoxContainer

## Base for swappable modal pick content (#486) — same "swap a pre-authored
## scene by context" shape [CommandTrayBodyBase] already uses (see that
## class's doc comment), keyed by which modal is presenting rather than
## attack mode. [ModalBase] instantiates exactly one of these into its
## %BodySlot per [method ModalBase.present] call and drives it purely through
## this contract:
##
##   - [method populate] builds this body's cards for a request.
##   - [signal selection_changed] — emit whenever a toggle may have changed
##     validity/status; [ModalBase] pulls [method is_selection_valid] /
##     [method status_text] in response (pull, not push, so the two never
##     drift out of sync).
##   - [method resolve] is pulled once, on confirm, only when
##     [method is_selection_valid] is true.
##
## Root is an HBoxContainer — the card row itself — mirroring the old
## LootPicker/SpellLootPicker `%CardRow`.

signal selection_changed()


## Build this body's cards for `request`. Concrete bodies narrow the type via
## `as` at the top (e.g. `request as LootPickRequest`) — Variant here because
## [ModalBase] itself is request-type-agnostic.
func populate(_request: Variant) -> void:
	pass


## True once exactly the required number of picks are selected.
func is_selection_valid() -> bool:
	return false


## Subtitle line, e.g. "Choose 2 of 4  (1 selected)".
func status_text() -> String:
	return ""


## The chosen subset. Only called when [method is_selection_valid] is true.
func resolve() -> Array:
	return []
