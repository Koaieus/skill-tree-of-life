@tool
class_name ExitConfirmPanel
extends FrontmatterPanel

## "Leave the tree?" — the panel EXIT raises before the game closes (#573).
##
## [b]This is deliberately not a modal-system modal.[/b]
## `.claude/rules/modal-system.md` routes a full-screen modal through
## [code]HudRoot._enqueue_modal[/code], and the frontmatter has no [HudRoot] —
## wiring one in to ask a yes/no question would drag the entire in-run HUD into
## the menu. It is a panel on the `%PanelLayer` like the other four, and #573
## says so explicitly.
##
## [b]It emits rather than quitting.[/b] [method SceneTree.quit] inside this
## script would end the process the moment a test pressed the button, which is
## exactly the trap `test_meta_routing_parity.gd` sidesteps today by asserting
## [code]MainMenuScreen.quit_pressed[/code]'s connection count instead of
## pressing it. So the shipped split survives the re-home unchanged: the panel
## emits [signal quit_requested], [FrontmatterPanels] relays it, and the shell
## decides that means quit — the same shape as
## [code]main.quit_pressed.connect(func(): get_tree().quit())[/code] in
## `meta_root.gd`.

## Emitted when the player confirms. Whoever composes the frontmatter shell
## connects this to [method SceneTree.quit]; nothing below that line quits.
signal quit_requested

@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		_confirm_button.pressed.connect(_on_confirm_pressed)


func _on_confirm_pressed() -> void:
	quit_requested.emit()
