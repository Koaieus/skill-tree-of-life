extends GutTest

## #1135 — restart is refused in a networked run: a mirror reloading alone
## desyncs from the rest of the peers, and host-broadcast restart is a
## separate feature, not this one. `GameSession.network` (never
## `GameSession.config.network` — [NetworkConfig] deliberately does not cross
## the wire as part of the run's config, `autoload/game_session.gd:60-68`) is
## the one fact both the guard and the button state read.

const _PAUSE_MENU := preload("res://ui/pause_menu.tscn")

var _menu: PauseMenu


func before_each() -> void:
	_menu = _PAUSE_MENU.instantiate()
	add_child_autofree(_menu)


func after_each() -> void:
	get_tree().paused = false
	GameSession.network = null
	GameSession.end()


func _go_online() -> void:
	var net := NetworkConfig.new()
	net.role = NetworkConfig.Role.HOST
	GameSession.network = net


func test_restart_button_disabled_when_online() -> void:
	_go_online()
	_menu.active = true
	var button: Button = _menu.get_node("%RestartButton")
	assert_true(button.disabled, "restart must be disabled in a networked run")


func test_restart_button_enabled_when_offline() -> void:
	_menu.active = true
	var button: Button = _menu.get_node("%RestartButton")
	assert_false(button.disabled, "restart stays enabled offline")


func test_restart_is_a_no_op_when_online() -> void:
	_go_online()
	_menu.active = true
	# `_restart()` would call `get_tree().reload_current_scene()`, which would
	# swap the running scene out from under the whole test suite — so the
	# online guard is asserted by its visible side effect instead: `active`
	# stays true (a real restart clears it before reloading).
	_menu._restart()
	assert_true(_menu.active, "a refused restart must not touch `active`")
