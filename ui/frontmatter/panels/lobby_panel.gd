@tool
class_name LobbyPanel
extends FrontmatterPanel

## The lobby, on the frontmatter's panel layer (#573).
##
## [b]This panel hosts the shipped [LobbyScreen]; it does not reimplement it.[/b]
## #573 is explicit that [method LobbyScreen.build_run_config] is #553/#554 work
## — the whole roster, the AI count, the seed sentinel, #554 D3's
## [method LobbyRoster.resolve_mode] at START — and that it must be re-homed
## rather than rewritten. #579 completed the move: the screen now lives beside
## this file and carries no chrome of its own, so what it contributes is the
## roster column and nothing else. Nothing here duplicates a decision that
## lives in it.
##
## [b]Order.[/b] [method configure] instances `lobby_screen.tscn`, hands it the
## route ([method LobbyScreen.configure], pure data), adds it under [member body]
## and only then calls [method LobbyScreen.refresh] — the one place the screen
## reads its roster. The screen is `_ready` long before that, so `_ready` builds
## nothing that depends on the route.
##
## The panel supplies the title and the back button; the screen supplies the
## rows. Before #579 it was the other way round — the screen carried inherited
## chrome and this panel blanked its own to avoid drawing two of everything.

## Relayed from the hosted screen. The shell decides that START means "open the
## run and load the level"; this panel only carries the [RunConfig] up.
signal start_pressed(run_config: RunConfig)

## Relayed from the hosted screen (#715). The host pressed START; this machine
## joined. Same relay, same shell decision, one fact different — the run is
## already open, so the shell routes without opening it.
signal remote_start(run_config: RunConfig)

const _LOBBY_SCREEN := preload("res://ui/frontmatter/panels/lobby_screen.tscn")

## The hosted screen, or null until [method configure] has run.
var screen: LobbyScreen = null


## Build the lobby for one menu route. [param mode] is the shape the route ASKED
## for, not the mode the run gets — [method LobbyRoster.resolve_mode] derives
## that from the roster at START (#554 D3).
##
## Calling this again replaces the screen, so backing out of a host route and
## taking a solo one does not leave the previous lobby's roster behind.
##
## [b]This does not touch [member GameSession.network].[/b] Re-stating the role
## on every route — including the offline ones, so a player who hosted and
## backed out does not silently open a socket — is `_push_lobby`'s decision and
## it stays in `meta_root.gd` until the cutover moves it. A panel that also
## wrote it would be a second place that decides, which is exactly the drift
## `test_meta_routing_parity.gd` exists to catch.
## [param policy] is what the route this lobby was opened from lets its slots
## choose (#615 D2). Null is legal and reproduces the pre-#615 lobby exactly.
func configure(
	mode: RunConfig.Mode, network: NetworkConfig = null, policy: LobbyPolicy = null
) -> void:
	if screen != null:
		body.remove_child(screen)
		screen.queue_free()
		screen = null

	var lobby: LobbyScreen = _LOBBY_SCREEN.instantiate()
	lobby.configure(mode, network, policy)
	lobby.start_pressed.connect(_on_start_pressed)
	lobby.remote_start.connect(_on_remote_start)
	body.add_child(lobby)
	lobby.refresh()
	screen = lobby


func _on_start_pressed(run_config: RunConfig) -> void:
	start_pressed.emit(run_config)


func _on_remote_start(run_config: RunConfig) -> void:
	remote_start.emit(run_config)
