class_name SpellCatalogueModal
extends ModalBase

## The spell catalogue as a full-screen modal (#853) — an inherited scene of
## `modal_base.tscn`, same shape as [MassActionConfirmPanel]: [ModalBase] owns
## the shell, the input freeze and the exits; [SpellCatalogueBody] owns the
## list. Read-only, so it is [member ModalBase.cancellable] (Esc / right-click
## close it) and its Confirm button reads CLOSE; there is nothing to resolve,
## so neither [signal ModalBase.confirmed] nor [signal ModalBase.cancelled] is
## listened to — [signal ModalBase.closed] is the only exit HudRoot needs.
##
## Raised from [PauseMenu] via [HudRoot]'s `_enqueue_modal`, while the tree is
## paused: `modal_base.tscn` runs PROCESS_MODE_ALWAYS, so the list scrolls and
## the buttons answer over a paused level, and HudRoot's modal-busy gate keeps
## Esc from reaching the pause menu underneath until this is down.

const _BODY_SCENE := preload("res://ui/spell_catalogue/spell_catalogue_body.tscn")


## Show the catalogue. No request — it is the same list for everyone.
func present() -> void:
	_present(_BODY_SCENE, "SPELL CATALOGUE", null)
