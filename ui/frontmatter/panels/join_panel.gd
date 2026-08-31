@tool
class_name JoinPanel
extends FrontmatterPanel

## The type-an-address panel JOIN raises before the lobby (#573, #582).
##
## [b]It carries an address AND a port, and nothing else.[/b] #582's owner call:
## [i]"join -- has option to select port (with default set to 9099) and or
## network address (whichever we need, likely both?)"[/i] — the answer is both,
## matching [method NetworkConfig.join]'s two arguments.
##
## [b]The Host and Hot-Seat buttons are gone (#582 acceptance 6).[/b] They were
## on the hosted `HostJoinScreen` from #531, when this was the only surface in
## the whole frontmatter that could accept a port — a [MenuGraph.Route] names a
## role, not digits, so routing HOST off the tree would have hosted on the
## default port forever. #579 wanted them trimmed and was right to be refused:
## trimming them then would have deleted the only port entry there was. Now
## [HostPanel] holds the host's port and the LOCAL leaf holds hot-seat, so the
## buttons are redundant in fact and not merely in appearance. The screen they
## lived on is gone with them; its address/port parsing survives, shared with
## the host panel, in [NetworkFields].

## The address and port the player typed. The shell turns this into
## `NetworkConfig.join(address, port)`; this panel does not construct one, for
## the same reason [LobbyPanel] does not write [member GameSession.network].
signal join_requested(address: String, port: int)

@onready var fields: NetworkFields = %NetworkFields
@onready var _join_button: Button = %JoinButton


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_join_button.pressed.connect(_on_join_pressed)


func _on_join_pressed() -> void:
	join_requested.emit(fields.address(), fields.port())
