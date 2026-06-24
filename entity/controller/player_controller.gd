class_name PlayerController
extends EntityController

## Human-driven turn: [method take_turn] is a no-op because the End Turn UI
## button drives [method TurnManager.end_turn] directly (via the global
## [PlayerInputController] sibling node which routes click input).
##
## Exists so the invariant "every Entity owns an EntityController child"
## holds for player entities too — without this, an authored player Entity
## with no controller would never see [method take_turn] fire (fine, since
## the UI handles it) but the invariant being broken made hand-authored
## sandbox scenes silently stall when nobody remembered to attach a
## controller to non-player entities either.
##
## [GameRoot._ensure_controllers] attaches this automatically post-
## [code]_setup_level()[/code] for any entity matching [member GameRoot.player]
## that lacks an EntityController child.


func take_turn() -> void:
	pass  # UI End Turn button calls turn_manager.end_turn() directly.
