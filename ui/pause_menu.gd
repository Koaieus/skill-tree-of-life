class_name PauseMenu
extends Control

## Single source of truth for the paused state. Toggling it shows/hides the menu
## and flips the SceneTree pause flag together. The node runs in
## PROCESS_MODE_ALWAYS (set in the scene) so it still catches the un-pause key
## and drives its buttons while the rest of the tree is frozen.
## The player asked to read the spell catalogue (#853). Emitted, not acted on:
## the catalogue is a modal-system modal and [HudRoot] owns the modal queue,
## so it is the one that presents it — same split as every other modal.
signal spell_catalogue_requested

@export var active: bool:
	set(v):
		if v == active: return
		active = v
		_toggle(active)


## Where SAVE goes and whether it may — the level's `%SaveGate`, set by
## [method HudRoot.bind_systems]. Unset (a menu instanced bare) leaves SAVE
## disabled.
@export var save_gate: SaveGate

@onready var _build_footer: Label = %BuildFooter
@onready var _restart_button: Button = %RestartButton
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _save_status: Label = %SaveStatus

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
	_update_restart_button()


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
	if on:
		_update_restart_button()
		_show_status("")
		_update_save_load_buttons()


## Reload the running level from scratch. `paused` is a SceneTree flag that
## survives the reload, so clear it first (via `active`) or the fresh scene boots
## frozen. No confirmation for now — straight restart.
##
## Refused in a networked run (#1135): a mirror reloading alone desyncs from
## the rest of the peers, and there is no host-broadcast restart (yet) to keep
## them in lockstep. The button is disabled with a tooltip for the same
## reason, so this guard only matters for the F5 shortcut.
func _restart() -> void:
	if GameSession.network != null and GameSession.network.is_online():
		return
	active = false
	get_tree().reload_current_scene()


## Disable + explain the restart button while a run is online; re-enable it
## otherwise. Called on `_ready` and on `_toggle` so a run that goes online
## mid-session (host starts a lobby from the pause menu, say) still reflects
## it next time the menu opens.
func _update_restart_button() -> void:
	var online := GameSession.network != null and GameSession.network.is_online()
	_restart_button.disabled = online
	_restart_button.tooltip_text = "Restart is disabled in a networked run." if online else ""


## SAVE copies RESTART's online gate, but asks [SaveGate] rather than restating
## it: the gate's [method SaveGate.blocked_reason] is the tooltip, both when
## SAVE is refused (online) and when a press would wait on the player (loot).
## LOAD is refused online too, and when there is no slot to read.
func _update_save_load_buttons() -> void:
	var gate := _resolve_save_gate()
	_save_button.disabled = gate == null or not gate.can_save()
	_save_button.tooltip_text = "No level to save." if gate == null else gate.blocked_reason()
	var online := GameSession.network != null and GameSession.network.is_online()
	var has_slot := SavedRun.has_slot(_slot_path())
	_load_button.disabled = online or not has_slot
	_load_button.tooltip_text = "No loading in an online run." if online \
			else SavedRun.describe(SaveFile.LoadResult.MISSING) if not has_slot else ""


## [member save_gate], with this menu's feedback hooked onto it on first use.
func _resolve_save_gate() -> SaveGate:
	if not is_instance_valid(save_gate):
		save_gate = null
	if save_gate != null and not save_gate.saved.is_connected(_on_saved):
		save_gate.saved.connect(_on_saved)
		save_gate.save_held_changed.connect(_on_save_held_changed)
	return save_gate


## One slot, and SAVE and LOAD must agree on it: the gate's when there is one.
func _slot_path() -> String:
	var gate := _resolve_save_gate()
	return gate.slot_path if gate != null else SaveFile.SLOT_PATH


func _on_save_button_pressed() -> void:
	var gate := _resolve_save_gate()
	if gate != null:
		gate.request_save()


func _on_saved(error: Error) -> void:
	_show_status("Saved." if error == OK else "Save failed: %s." % error_string(error))
	_update_save_load_buttons()


func _on_save_held_changed(held: bool) -> void:
	if held:
		_show_status("Saving once this move settles…")


## LOAD: open the slot, then leave for its level — unpausing first, for the
## same reason [method leave_run] does. A refused file stays on this menu and
## says why.
func _on_load_button_pressed() -> void:
	var save := load_saved()
	if save.load_result != SaveFile.LoadResult.OK:
		return
	active = false
	SavedRun.route(save)


## The testable half of LOAD: reads the slot and opens it on [GameSession] via
## [SavedRun], the path the frontmatter's LOAD GAME shares. A refused file
## leaves the running run alone and shows its reason.
func load_saved() -> SaveFile:
	var save := SavedRun.open(_slot_path())
	_show_status(SavedRun.describe(save.load_result))
	return save


func _show_status(text: String) -> void:
	_save_status.text = text
	_save_status.visible = not text.is_empty()


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


## Ask for the catalogue; the menu stays up (and the tree paused) underneath
## it, so closing the catalogue lands the player back here.
func _on_spell_catalogue_button_pressed() -> void:
	spell_catalogue_requested.emit()


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
