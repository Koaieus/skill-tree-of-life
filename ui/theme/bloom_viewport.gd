@tool
extends SubViewport
## The packaged bloom-capable `SubViewport` (#371) — `own_world_3d` +
## `use_hdr_2d` + a `WorldEnvironment`, all three of which are required and all
## three of which fail silently when missed.
##
## The script exists for exactly one reason: the packaged `WorldEnvironment` is
## *internal* to this instance, so `%WorldEnvironment` does not resolve from the
## scene that instances it. A tuning panel therefore has no way to reach the
## Environment that is actually rendering — and the previous answer, "resources
## are cached by path, so `load()` hands back the same instance", is an
## assumption about the resource cache rather than a fact about this tree. It was
## never checked in the editor, which is where every tuning panel lives. The
## scene hands the object out itself instead; identity is true by construction,
## and the Bloom tab prints both instance ids so a future divergence is visible
## rather than silent.


func _ready() -> void:
	# A viewport's environment mode defaults to INHERIT — it takes the setting
	# from its PARENT viewport rather than deciding for itself. In a game the
	# parent chain ends at the root, environments are on, and everything works.
	# Inside an editor dock/main screen the parent is the editor's own window
	# viewport, which has environments disabled (the editor UI must not be
	# post-processed) — so the SubViewport silently inherits "no environment" and
	# the glow pass never runs, while `own_world_3d`, `use_hdr_2d`, the registered
	# Environment and the HDR render target all still read perfectly correct.
	#
	# This is why the same scene blooms on the editor's 2D screen (parented under
	# EditorNode's scene-root SubViewport, environments enabled) and not in the
	# sandbox host.
	#
	# Do not remove this again. 6014649 added it while the panel was still
	# `add_child`ed from an `@export` — non-scenic composition in place — and the
	# tab bloomed, so this line alone is sufficient. 9dcc89c then baked the panel
	# into its tab scene and reverted this on the theory that baking was the real
	# fix; that measurement was taken with this forcing still live, and dropping
	# it put the tab straight back to inert. Baking stays (the sandbox-host rule
	# wants it regardless), but it is not what makes the pass run.
	# See `docs/domain/hdr-color.md`.
	RenderingServer.viewport_set_environment_mode(
		get_viewport_rid(), RenderingServer.VIEWPORT_ENVIRONMENT_ENABLED
	)


## The `Environment` this viewport's glow pass is running. Mutate it to drive the
## live pass; it is the shared `default_game_env.tres`, never a copy.
func get_environment_resource() -> Environment:
	var world_env := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	return world_env.environment if world_env != null else null
