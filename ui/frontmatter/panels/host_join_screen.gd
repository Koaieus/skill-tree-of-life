class_name HostJoinScreen
extends VBoxContainer

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
## sequenced, not merged.

signal host_pressed(port: int)
signal join_pressed(address: String, port: int)
## Two humans, one machine, no wire — the shape the Multiplayer button used to
## go straight to.
signal hotseat_pressed

## The rows this screen stacks, kept under the name the shipped code and its
## tests already use. It is this node: the screen IS its own column now that
## [FrontmatterPanel] supplies the frame, the title and the back button around
## it (#579). Before the cutover this was a child [VBoxContainer] built by
## the deleted `MenuScreen._ready`, which also drew a background and a title bar
## — chrome that would be drawn twice inside a panel.
var content: VBoxContainer:
	get:
		return self


## Adds a Button to [member content]. Caller connects `.pressed` itself.
##
## Duplicated in [LobbyScreen] rather than shared through a common base: the
## base that used to own it was `MenuScreen`, and #579 deletes it. Seven lines
## of widget construction in two files beats a new base class whose whole reason
## to exist is those seven lines.
func add_option(text: String, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	content.add_child(button)
	return button

var _address_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 8)

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
## they were left alone by the deleted stack's interactivity toggle — a field on
## a screen that was no longer on top stayed visible but unreachable behind the
## pushed one. Nothing stacks any more; the note survives as the reason these
## rows are built as rows rather than as options.
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
