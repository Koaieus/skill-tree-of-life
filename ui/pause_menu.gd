class_name PauseMenu
extends Control

## Single source of truth for the paused state. Toggling it shows/hides the menu
## and flips the SceneTree pause flag together. The node runs in
## PROCESS_MODE_ALWAYS (set in the scene) so it still catches the un-pause key
## and drives its buttons while the rest of the tree is frozen.
@export var active: bool:
	set(v):
		if v == active: return
		active = v
		_toggle(active)


@onready var _build_footer: Label = %BuildFooter

## True while a picker modal (LootPicker/SpellLootPicker, #486) is up. Esc
## would otherwise fall through to here and open the pause menu on top of a
## frozen pick — set by HudRoot alongside its `_modal_busy` lifecycle.
var _blocked: bool = false


func set_blocked(blocked: bool) -> void:
	_blocked = blocked


func _ready() -> void:
	# Start hidden + unpaused regardless of the editor-saved `visible`.
	visible = false
	# Gated on KNOWING a sha, not on [member BuildInfo.is_dev]: since exports
	# carry a build stamp, a LAN build can answer "which build is this machine
	# running" without the operator diffing two exes. A build with no stamp
	# still hides it.
	var identified := not BuildInfo.short_sha.is_empty()
	_build_footer.visible = identified
	if identified:
		_build_footer.text = _footer_text()
		_build_footer.gui_input.connect(_on_build_footer_gui_input)


func _footer_text() -> String:
	var wt_part := ("wt:%s @ " % BuildInfo.worktree) if not BuildInfo.worktree.is_empty() \
			else "%s @ " % BuildInfo.branch
	return "seed %s  ·  %s%s" % [_current_seed_text(), wt_part, BuildInfo.short_sha]


## The run's resolved seed (#457) — concrete for the whole run, so this is the
## number to copy and type back into the lobby to replay the same map. An em
## dash means no run is live (this menu shouldn't be reachable then, but the
## footer must never lie about a seed it doesn't have).
func _current_seed_text() -> String:
	return str(GameSession.config.seed) if GameSession.is_active() else "—"


func _on_build_footer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.clipboard_set(_current_seed_text())


func _toggle(on: bool) -> void:
	visible = on
	get_tree().paused = on


## Reload the running level from scratch. `paused` is a SceneTree flag that
## survives the reload, so clear it first (via `active`) or the fresh scene boots
## frozen. No confirmation for now — straight restart.
func _restart() -> void:
	active = false
	get_tree().reload_current_scene()


func _on_restart_button_pressed() -> void:
	_restart()


## Abandon the run and go back to the frontmatter menu. Straight out, no
## confirmation — same call the sibling [method _restart] already makes.
func _on_to_main_menu_button_pressed() -> void:
	leave_run()
	# [constant GameRoot.META_ROOT], not a second copy of the path: a finished
	# run already routes there (#460), and "where is the main menu" gets one
	# answer. `test/unit/ui/test_pause_menu.gd` pins it against
	# `application/run/main_scene` so neither site can go stale.
	SceneDirector.goto(GameRoot.META_ROOT)


## The tear-down half of leaving, split out because the [SceneDirector] half
## cannot be exercised from a test without actually swapping the running scene.
##
## Unpausing FIRST is load-bearing, and for a stronger reason than `paused`
## outliving the scene swap: [SceneTransition] is a PAUSABLE autoload, so its
## fade-out never finishes while the tree is frozen and
## [method SceneDirector.goto] would await forever — the button would look dead.
##
## [method GameSession.end] then closes the run so the next one starts clean;
## in particular its [NetworkConfig] must not survive, or a player who hosted
## and then backed out silently opens a socket again. No
## [signal Events.run_ended] — [VictorySystem] is the sole emitter of that, and
## walking out is not an outcome.
func leave_run() -> void:
	active = false
	GameSession.end()


## Quit the application. `get_tree().quit()` requests a clean shutdown — the
## engine finishes the frame, runs NOTIFICATION_WM_CLOSE_REQUEST / _exit_tree,
## then closes. (Editor: stops the play session.)
func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_continue_button_pressed() -> void:
	active = false


## Esc toggles pause from either state. Routed through `active` so the export
## stays truthful. Runs in any process mode because the node is ALWAYS.
func _unhandled_key_input(event: InputEvent) -> void:
	if _blocked:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		active = not active
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F5:
		get_viewport().set_input_as_handled()
		_restart()
