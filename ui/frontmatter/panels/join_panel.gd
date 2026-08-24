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
## [b]The Host and Hot-Seat buttons stay, and that is a decision, not an
## oversight.[/b] They look redundant — the frontmatter tree offers HOST and
## LOCAL as their own leaves — but they are the only place a PORT can be typed.
## A leaf carries a [MenuGraph.Route], which names a role and nothing else, so
## routing HOST straight off the tree hosts on the default port forever. #531's
## screen is what makes `NetworkConfig.host(<typed port>)` reachable at all, and
## `test_host_join_screen.gd` pins all three buttons besides. Removing them
## would delete shipped behaviour and the assertions over it; see #579's report.

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


func _on_join_pressed(address: String, port: int) -> void:
	join_requested.emit(address, port)


func _on_host_pressed(port: int) -> void:
	host_requested.emit(port)


func _on_hotseat_pressed() -> void:
	hotseat_requested.emit()
