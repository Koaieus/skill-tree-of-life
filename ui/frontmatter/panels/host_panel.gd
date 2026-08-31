@tool
class_name HostPanel
extends FrontmatterPanel

## The host's pre-lobby config panel (#582).
##
## [b]Why HOST gets a screen of its own.[/b] Owner, 2026-08-31: [i]"host -- has
## option to select port (with default set to 9099) -> upon starting the host
## session they join the lobby"[/i]. HOST used to route straight onto the lobby
## from its leaf, which meant it hosted on [constant NetworkConfig.DEFAULT_PORT]
## forever — a [MenuGraph.Route] names a role, not digits.
##
## [b]It sits before the lobby, not inside it, because of an ordering
## constraint.[/b] [method MetaRoot._on_host_requested] builds
## `NetworkConfig.host(port)` and hands it to [method LobbyPanel.configure],
## whose screen branches on that config in `_ready` — so the port has to be
## settled on the way IN. A port field in the lobby would mean rebuilding the
## config the lobby was already configured with.
##
## [b]The other run settings stay in the lobby[/b] (#582 D5) — AI count, mode,
## seed are [method LobbyScreen.build_run_config]'s (#553/#554) and do not
## migrate forward. This panel is free to grow further HOST-SIDE, pre-lobby
## settings; it is not a second lobby.
##
## No address row: a listener binds every interface rather than dialling one
## ([member NetworkFields.show_address]). Where this machine can be REACHED is
## read out by the lobby once hosting starts (#582 acceptance 3).

## The port this machine should listen on. The shell turns it into
## `NetworkConfig.host(port)` and pushes the lobby — same relay shape as
## [signal JoinPanel.join_requested], and for the same reason: a panel reports
## what was typed, it does not decide what a route means.
signal host_requested(port: int)

@onready var fields: NetworkFields = %NetworkFields
@onready var _host_button: Button = %HostButton


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_host_button.pressed.connect(_on_host_pressed)


func _on_host_pressed() -> void:
	host_requested.emit(fields.port())
