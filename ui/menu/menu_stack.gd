class_name MenuStack
extends Control

## Breadcrumb container for [MenuScreen] levels. Deliberately a plain
## Control, not a Container — Container layout would fight the per-panel
## `scale` used for the shrink effect, so panels are positioned by hand in
## [method _relayout]. Pushing a screen keeps every ancestor screen alive
## (just dimmed + non-interactive) so a future pan/zoom polish pass has
## something to animate; this pass only does the instant layout.

## Horizontal offset per ancestor level; smaller than panel width so ~1.5
## layers stay visible behind the active one.
const STEP_X := 300.0

## Emitted when the last screen is popped (stack goes empty).
signal emptied

var _screens: Array[MenuScreen] = []


func push(screen: MenuScreen) -> MenuScreen:
	add_child(screen)
	screen.back_requested.connect(_on_screen_back_requested.bind(screen))
	_screens.append(screen)
	_relayout()
	return screen


func pop() -> void:
	if _screens.is_empty():
		return
	var top: MenuScreen = _screens.pop_back()
	top.queue_free()
	_relayout()
	if _screens.is_empty():
		emptied.emit()


func _on_screen_back_requested(screen: MenuScreen) -> void:
	if screen != _screens.back():
		return  # stale signal from an already-popped screen
	pop()


func _relayout() -> void:
	var n := _screens.size()
	for i in n:
		var screen: MenuScreen = _screens[i]
		var depth := n - 1 - i  # 0 = active/top, 1 = its parent level, ...
		var s: float = 1.0 if depth == 0 else maxf(0.6, 1.0 - depth * 0.15)
		screen.pivot_offset = screen.panel_size / 2.0
		screen.scale = Vector2(s, s)
		var center: Vector2 = size / 2.0 - Vector2(depth * STEP_X, 0.0)
		screen.position = center - screen.panel_size / 2.0
		screen.modulate.a = 1.0 if depth == 0 else 0.45
		screen.set_interactive(depth == 0)
		screen.z_index = n - depth
