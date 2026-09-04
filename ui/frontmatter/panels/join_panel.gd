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
##
## [b]Never emitted for an address that cannot be dialled (#752).[/b] The one
## such address is a blank one — it used to fall back to loopback, and a joiner
## who left the box alone dialled itself. The refusal is spoken on the panel
## ([member _status_label]) and the fields stay put for the retry.
signal join_requested(address: String, port: int)

@onready var fields: NetworkFields = %NetworkFields
@onready var _join_button: Button = %JoinButton
## The inline refusal. Blank while nothing is wrong; cleared again by the next
## press that goes through, so a corrected address does not carry the old
## complaint into the lobby.
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_join_button.pressed.connect(_on_join_pressed)


func _on_join_pressed() -> void:
	var address := fields.address()
	var problem := NetworkConfig.join_address_problem(address)
	_status_label.text = problem
	if not problem.is_empty():
		return
	join_requested.emit(address, fields.port())


## The refusal currently shown, or `""`. Public so a test can read it without
## reaching into a private child — the same courtesy [method LobbyScreen.status_text]
## extends.
func status_text() -> String:
	return "" if _status_label == null else _status_label.text
