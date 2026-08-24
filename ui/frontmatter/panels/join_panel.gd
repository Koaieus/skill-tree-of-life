@tool
class_name JoinPanel
extends FrontmatterPanel

## The type-an-address panel JOIN raises before the lobby (#573).
##
## [b]This panel hosts the shipped [HostJoinScreen] as-is.[/b] #573 names its
## address/port handling and its `_address()` fallback as things to re-home
## rather than rewrite, so the screen is instanced whole and its three signals
## are relayed. Unlike [LobbyPanel] it can sit in the `.tscn`: [HostJoinScreen]
## has no configure-before-ready contract — it builds its two fields and its
## buttons in `_ready` and reads them only when pressed.
##
## [b]Known redundancy, deliberate, and it goes at the cutover.[/b] The screen
## carries Host / Join / Hot-Seat because #531 put one screen between
## "Multiplayer" and the lobby. The frontmatter tree splits those into three
## sibling leaves (`ID_HOST`, `ID_JOIN`, `ID_LOCAL`), and only JOIN routes here
## — so the Host and Hot-Seat buttons on this panel duplicate leaves the graph
## already offers. Trimming them means editing [HostJoinScreen], which is a
## rewrite of shipped #531 work and out of this unit's scope; all three signals
## are relayed so nothing is lost either way, and the trim happens when the
## screen physically moves. [signal host_requested] and
## [signal hotseat_requested] exist so that redundancy is at least addressable
## rather than silently dead.

## The address and port the player typed. The shell turns this into
## `NetworkConfig.join(address, port)`; this panel does not construct one, for
## the same reason [LobbyPanel] does not write [member GameSession.network].
signal join_requested(address: String, port: int)
## Relayed from the hosted screen's redundant Host button — see the class note.
signal host_requested(port: int)
## Relayed from the hosted screen's redundant Hot-Seat button — see the class note.
signal hotseat_requested

@onready var screen: HostJoinScreen = %HostJoinScreen


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	screen.join_pressed.connect(_on_join_pressed)
	screen.host_pressed.connect(_on_host_pressed)
	screen.hotseat_pressed.connect(_on_hotseat_pressed)
	screen.back_requested.connect(dismiss)


func _on_join_pressed(address: String, port: int) -> void:
	join_requested.emit(address, port)


func _on_host_pressed(port: int) -> void:
	host_requested.emit(port)


func _on_hotseat_pressed() -> void:
	hotseat_requested.emit()
