class_name HostJoinScreen
extends MenuScreen

## The type-an-IP screen (#531): the step between Multiplayer and the lobby.
##
## [b]Discovery is typing an address.[/b] LAN broadcast was evaluated and
## dropped — one room, one number, not worth the ceremony (#463's body).
##
## [b]It decides a role, not a run.[/b] Every button here pushes the SAME
## lobby; all that differs is the [NetworkConfig] left on [GameSession] for the
## level to pick up. That is the "roster-driven, no coop/versus branch"
## decision showing up as an absence: there is no host-lobby and no join-lobby.
##
## [b]This is the plainest functional thing on purpose.[/b] #461 is looks and
## UX and owns styling this later; per the owner's 2026-08-22 call the two are
## sequenced, not merged. Same code-composed chrome as every other [MenuScreen]
## — no scene file.

signal host_pressed(port: int)
signal join_pressed(address: String, port: int)
## Two humans, one machine, no wire — the shape the Multiplayer button used to
## go straight to.
signal hotseat_pressed

var _address_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	super._ready()
	set_title("Multiplayer")

	_address_edit = _add_field("Address:", NetworkConfig.DEFAULT_ADDRESS)
	_port_edit = _add_field("Port:", str(NetworkConfig.DEFAULT_PORT))

	add_option("Host").pressed.connect(func(): host_pressed.emit(_port()))
	add_option("Join").pressed.connect(
			func(): join_pressed.emit(_address(), _port()))
	add_option("Hot-Seat (this machine)").pressed.connect(func(): hotseat_pressed.emit())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	# The honest caption for what this can and cannot do yet. Run settings do
	# not cross the wire until #533, so the two peers agree on a map only by
	# both people typing the same seed. Saying so here beats a player
	# discovering it as a DIVERGED line in a log they never open.
	var hint := Label.new()
	hint.text = "Both players must type the same seed in the lobby."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	content.add_child(hint)


## A labelled [LineEdit] row in [member content]. Rows are not buttons, so
## [method MenuScreen.set_interactive] leaves their `mouse_filter` alone — a
## field on a screen that is no longer on top stays visible but unreachable
## behind the pushed screen, which is what the stack already relies on.
func _add_field(label_text: String, initial: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)

	var label := Label.new()
	label.text = label_text
	row.add_child(label)

	var edit := LineEdit.new()
	edit.text = initial
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


## Blank falls back to the default rather than dialling "" — a typo'd address
## should fail at the socket with a message, not here with a silent no-op.
func _address() -> String:
	var text := _address_edit.text.strip_edges()
	return text if not text.is_empty() else NetworkConfig.DEFAULT_ADDRESS


func _port() -> int:
	var text := _port_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() else NetworkConfig.DEFAULT_PORT
