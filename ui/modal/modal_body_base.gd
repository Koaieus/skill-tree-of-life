@tool
class_name ModalBodyBase
extends Container

## Base for swappable modal content (#486) — same "swap a pre-authored scene by
## context" shape [CommandTrayBodyBase] already uses (see that class's doc
## comment), keyed by which modal is presenting rather than attack mode.
## [ModalBase] instantiates exactly one of these into its %BodySlot per
## `_present()` call and drives it purely through this contract:
##
##   - [method populate] builds this body's content for a request.
##   - [signal selection_changed] — emit whenever something may have changed
##     validity/status; [ModalBase] pulls [method is_selection_valid] /
##     [method status_text] / [method confirm_text] in response (pull, not
##     push, so the two never drift out of sync).
##   - [method resolve] is pulled once, on confirm, only when
##     [method is_selection_valid] is true.
##
## Extends [Container] rather than a concrete one so each body scene picks its
## own layout root: a card row is an [HBoxContainer], a scrolling breakdown is
## a [VBoxContainer]. (A script may extend an ANCESTOR of its node's type.)
## %BodySlot is a [CenterContainer], which hands a child exactly its combined
## minimum size — a body that needs to scroll must say so with
## `custom_minimum_size`, not with size flags.

signal selection_changed()


## Build this body's content for `request`. Concrete bodies narrow the type via
## `as` at the top (e.g. `request as LootPickRequest`) — Variant here because
## [ModalBase] itself is request-type-agnostic.
func populate(_request: Variant) -> void:
	pass


## Is the Confirm button live? A picker answers "exactly one card picked"; a
## yes/no confirm answers "can this even be afforded".
func is_selection_valid() -> bool:
	return false


## Subtitle line, e.g. "Choose 1 of 4" or "3 Skill Points — reaches 2 of 5".
func status_text() -> String:
	return ""


## Overrides the Confirm button's authored label when non-empty — for a body
## whose verb depends on the request ("ALLOCATE" vs "DEALLOCATE"). Empty (the
## default) keeps whatever the inherited scene authored.
func confirm_text() -> String:
	return ""


## The chosen subset, empty for a body with nothing to select. Only called
## when [method is_selection_valid] is true.
func resolve() -> Array:
	return []
