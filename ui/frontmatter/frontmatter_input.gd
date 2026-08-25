@tool
class_name FrontmatterInput
extends Node

## Keyboard and gamepad navigation for the frontmatter (#576).
##
## [b]The menu is a graph, so the input is directional.[/b] The focused node is
## the hero; its children are the fan to its right. `ui_up`/`ui_down` move a
## CURSOR through that fan, `ui_accept`/`ui_right` commits to the cursor, and
## `ui_cancel`/`ui_left` goes back. Every one of those ends in a call
## [FrontmatterRoot] already exposes — this file adds no navigation of its own,
## because a second thing that moves the camera is a second thing that can
## disagree with [method FrontmatterRoot.navigation_state].
##
## [b]The cursor is not the focus.[/b] Focus is where the camera IS; the cursor
## is which sibling a commit would take. They are different questions — at
## `single_player` the camera sits on Single Player while the cursor picks
## between New Game and Load Game — and conflating them would make merely
## looking at an option navigate to it.
##
## [b]Keyboard focus counts as hover, deliberately.[/b] The cursor calls
## [method FrontmatterRoot.set_hovered], so moving it raises the same peek and
## tooltip the mouse would. #576's note forbids inventing a seventh ring colour
## and asks for an existing focus treatment to be reused instead — this is that
## reuse, and it is the whole reason a keyboard player can see what a commit
## would do before making it. There is no disagreement to manage between the two
## today: [MenuNodeView] has no pick region at all yet, so mouse hover does not
## fire (#583).
##
## [b]Mounting.[/b] Add as a child of [FrontmatterRoot] with
## [member frontmatter_path] pointing at it, or call [method bind] from a
## composer. It reads input through `_unhandled_input`, so anything a focused
## [Control] in the panel layer consumes first — typing into the seed field, a
## button press — never reaches here.

## Face buttons this menu answers to ON TOP of the `ui_*` actions.
##
## [b]A stopgap, and the real fix is one line of `project.godot`.[/b] Probed
## 2026-08-25: this project's `ui_accept` is bound to Enter / Kp Enter / Space
## and `ui_cancel` to Escape — **neither carries a joypad event**, while
## `ui_up`/`ui_down`/`ui_left`/`ui_right` all carry D-pad and stick bindings. So
## a controller can already walk the menu (D-pad right commits, D-pad left goes
## back) but the two buttons every player reaches for first do nothing.
##
## Adding `JOY_BUTTON_A` to `ui_accept` and `JOY_BUTTON_B` to `ui_cancel` in the
## project input map is the correct fix — global, remappable, and it would let
## these two constants be deleted. `project.godot` is outside #576's file list,
## so this covers the menu until that lands. See the unit's report.
const JOY_ACCEPT := JOY_BUTTON_A
const JOY_CANCEL := JOY_BUTTON_B

## The frontmatter this drives. Injected as a NodePath by the composing scene
## per `.claude/rules/scene-composition.md`.
@export var frontmatter_path: NodePath

## Which sibling in the current fan a commit would take, or `&""` when the
## focused node is a leaf and there is nothing to pick.
var cursor: StringName = &"":
	get:
		return cursor

var _frontmatter: FrontmatterRoot = null


func _ready() -> void:
	if frontmatter_path.is_empty():
		return
	bind(get_node_or_null(frontmatter_path) as FrontmatterRoot)


## Points this at a frontmatter and seats the cursor on its first option.
## Idempotent, so a rebuild (#578's live tab) can re-bind without stacking
## connections.
func bind(frontmatter: FrontmatterRoot) -> void:
	if _frontmatter != null:
		if _frontmatter.focus_changed.is_connected(_on_focus_changed):
			_frontmatter.focus_changed.disconnect(_on_focus_changed)
		if _frontmatter.focus_started.is_connected(_on_focus_started):
			_frontmatter.focus_started.disconnect(_on_focus_started)
	_frontmatter = frontmatter
	if _frontmatter == null:
		return
	if not _frontmatter.focus_changed.is_connected(_on_focus_changed):
		_frontmatter.focus_changed.connect(_on_focus_changed)
	if not _frontmatter.focus_started.is_connected(_on_focus_started):
		_frontmatter.focus_started.connect(_on_focus_started)
	_seat_cursor()


func _unhandled_input(event: InputEvent) -> void:
	if _frontmatter == null or _frontmatter.tree == null:
		return
	if not (event.is_pressed() and not event.is_echo()):
		return
	if _handle(event):
		get_viewport().set_input_as_handled()


## The whole input contract as one function of an event, so a test drives it
## with a synthesized [InputEventKey] or [InputEventJoypadButton] and reads the
## resulting focus — no viewport, no frame, no real input map plumbing.
## Returns whether the event was consumed.
func _handle(event: InputEvent) -> bool:
	# A raised panel owns the keyboard: its own Controls handle up/down/accept,
	# and the only thing this layer still answers for is the way out.
	if _panel_is_up():
		if _is_cancel(event):
			dismiss_panel()
			return true
		return false

	if event.is_action_pressed(&"ui_up"):
		return step(-1)
	if event.is_action_pressed(&"ui_down"):
		return step(1)
	if _is_accept(event) or event.is_action_pressed(&"ui_right"):
		return commit()
	if _is_cancel(event) or event.is_action_pressed(&"ui_left"):
		return back()
	return false


static func _is_accept(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_accept") or _is_face_button(event, JOY_ACCEPT)


static func _is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel") or _is_face_button(event, JOY_CANCEL)


static func _is_face_button(event: InputEvent, button: JoyButton) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button


## Moves the cursor [param delta] places through the current fan.
##
## [b]It wraps.[/b] A fan is two to four items, and clamping a four-item menu
## makes the last `ui_down` feel like a dropped input rather than an edge. #576
## allows either as long as one is pinned; `test_frontmatter_input.gd` pins this.
func step(delta: int) -> bool:
	var options := _options()
	if options.is_empty():
		return false
	var at := options.find(cursor)
	var next := 0 if at < 0 else posmod(at + delta, options.size())
	_move_cursor(options[next])
	return true


## Navigates to the cursor. A disabled option (LOAD GAME, while #23 is parked)
## is consumed rather than followed — the press did something, it just refuses,
## which is a better answer than the input falling through to `back()`.
func commit() -> bool:
	if cursor == &"" or not _frontmatter.tree.has(cursor):
		return false
	var item := _frontmatter.tree.get_item(cursor)
	if item != null and item.disabled:
		return true
	_frontmatter.focus(cursor)
	return true


## Up one level. A no-op at the root, where it is still CONSUMED — see
## [method _handle]: reporting "not handled" there would let `ui_cancel` fall
## through to whatever sits behind the menu.
func back() -> bool:
	_frontmatter.back()
	return true


## Closes the raised panel through the panel's own dismissal seam, so the shell
## hears [signal FrontmatterPanels.panel_dismissed] exactly as it would from a
## clicked back button and answers it in one place.
func dismiss_panel() -> void:
	var panels := _panels()
	if panels == null:
		return
	var panel := panels.get_panel(panels.shown_panel)
	if panel != null:
		panel.dismiss()
	else:
		panels.hide_all()


## Hands the keyboard to the raised panel, so a controller player is not left
## with a lit-up panel and no way into it.
func grab_panel_focus() -> void:
	var panels := _panels()
	if panels == null:
		return
	var panel := panels.get_panel(panels.shown_panel)
	if panel != null and panel.back_button != null and panel.back_button.visible:
		panel.back_button.grab_focus()


## The focus has CHANGED, so the fan the cursor picks from has changed with it —
## reseat immediately, while the camera is still travelling.
##
## [b]The cursor must never outlive the fan it was seated in.[/b] It used to be
## reseated on [signal FrontmatterRoot.focus_changed], which fires on ARRIVAL, so
## for the whole 850ms of travel `cursor` still named a child of the node being
## left behind. `ui_left` then `ui_right` mid-flight read as "go back, then
## commit to a node that is now a GRANDCHILD" and skipped a level. Departure is
## the only correct moment: focus is a fact about where the menu IS going.
func _on_focus_started(_id: StringName) -> void:
	_seat_cursor()


## The camera has ARRIVED. The cursor is already correct (see
## [method _on_focus_started]); what is left is the thing that genuinely needs a
## settled menu — handing the keyboard to a panel that has just been raised,
## which only happens at `t == 1`.
func _on_focus_changed(_id: StringName) -> void:
	if _panel_is_up():
		grab_panel_focus()


## Puts the cursor on the first option of the new fan — or nowhere, on a leaf.
func _seat_cursor() -> void:
	var options := _options()
	_move_cursor(options[0] if not options.is_empty() else &"")


func _move_cursor(id: StringName) -> void:
	cursor = id
	if _frontmatter != null:
		_frontmatter.set_hovered(id)


func _options() -> Array[StringName]:
	if _frontmatter == null or _frontmatter.tree == null:
		var none: Array[StringName] = []
		return none
	return _frontmatter.tree.children_of(_frontmatter.focus_id)


func _panels() -> FrontmatterPanels:
	if _frontmatter == null:
		return null
	var found := _frontmatter.find_children("*", "FrontmatterPanels", true, false)
	return null if found.is_empty() else found[0] as FrontmatterPanels


func _panel_is_up() -> bool:
	var panels := _panels()
	return panels != null and panels.shown_panel != &"" and panels.visible
