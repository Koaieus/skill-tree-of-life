@tool
class_name LobbyPanel
extends FrontmatterPanel

## The lobby, on the frontmatter's panel layer (#573).
##
## [b]This panel hosts the shipped [LobbyScreen]; it does not reimplement it.[/b]
## #573 is explicit that [method LobbyScreen.build_run_config] is #553/#554 work
## — the whole roster, the AI count, the seed sentinel, #554 D3's
## [method LobbyScreen.resolve_mode] at START — and that it must be re-homed
## rather than rewritten. #579 completed the move: the screen now lives beside
## this file and carries no chrome of its own, so what it contributes is the
## roster column and nothing else. Nothing here duplicates a decision that
## lives in it.
##
## [b]Why the screen is built in code rather than sitting in this scene.[/b]
## [method LobbyScreen.configure] documents its own ordering: it must be called
## before the screen enters the tree, because `_ready` branches on the
## [NetworkConfig] to decide whether the lobby even offers an AI-opponent row.
## A screen parked in the `.tscn` is already `_ready` by the time a caller could
## configure it, so it would silently build the wrong shape. Hence
## [method configure] mints it — the same `LobbyScreen.new()` + `configure()`
## order `meta_root.gd`'s `_push_lobby` uses today, and the reason
## `.claude/rules/scene-composition.md`'s "prefer a `.tscn`" does not apply:
## [LobbyScreen] has no scene to instance, and building one would be the rewrite
## this unit must not do.
##
## The panel supplies the title and the back button; the screen supplies the
## rows. Before #579 it was the other way round — the screen carried inherited
## chrome and this panel blanked its own to avoid drawing two of everything.

## Relayed from the hosted screen. The shell decides that START means "open the
## run and load the level"; this panel only carries the [RunConfig] up.
signal start_pressed(run_config: RunConfig)

## The hosted screen, or null until [method configure] has run.
var screen: LobbyScreen = null


## Build the lobby for one menu route. [param mode] is the shape the route ASKED
## for, not the mode the run gets — [method LobbyScreen.resolve_mode] derives
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
func configure(mode: RunConfig.Mode, network: NetworkConfig = null) -> void:
	if screen != null:
		body.remove_child(screen)
		screen.queue_free()
		screen = null

	var lobby := LobbyScreen.new()
	lobby.configure(mode, network)
	lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby.start_pressed.connect(_on_start_pressed)
	body.add_child(lobby)
	screen = lobby


func _on_start_pressed(run_config: RunConfig) -> void:
	start_pressed.emit(run_config)
