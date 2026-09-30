class_name CoreMoveMode
extends ArmedMode

## Core-move targeting from [member source] (the player's core). The next click
## is the target: an owned node commits the move, the core itself cancels, and
## anything else cancels and FALLS THROUGH so the root's allocate still runs
## without a second click. Drag-to-move is the controller's; it reads
## [member source] off this level.

const _ICON := preload("res://assets/icons/addons/armed_move_core.png")
const _PALETTE := preload("res://ui/theme/action_palette.tres")

var source: SkillNode


func _init(p_ctl: PlayerInputController, p_source: SkillNode) -> void:
	ctl = p_ctl
	source = p_source


func handle_left_click(node: SkillNode) -> bool:
	if not ctl._player_has_movement_points():
		pop_self()
		return false
	if node == source:
		pop_self()
		return true
	if node.owned_by == ctl.player:
		ctl._commit_core_move(node)
		pop_self()
		return true
	pop_self()
	return false


func on_popped() -> void:
	ctl._clear_core_drag()


func icon() -> Texture2D:
	return _ICON


func icon_tint() -> Color:
	return _PALETTE.color_for(&"move_core")
