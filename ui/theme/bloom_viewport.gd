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
	# A viewport's environment mode defaults to INHERIT — it takes the setting from
	# its PARENT viewport rather than deciding for itself. In a game the parent
	# chain ends at the root, environments are on, and everything works. Inside an
	# editor dock the parent is the editor's own main window, which has
	# environments disabled (the editor UI must not be post-processed) — so the
	# SubViewport silently inherits "no environment" and the glow pass never runs,
	# while `own_world_3d`, `use_hdr_2d`, the registered Environment and the HDR
	# render target all still read perfectly correct. Force it on.
	#
	# This is why the same scene blooms on the 2D screen (parented under the
	# editor's scene-root SubViewport, environments enabled) and not in the
	# sandbox dock. See `docs/domain/hdr-color.md`.
	RenderingServer.viewport_set_environment_mode(
		get_viewport_rid(), RenderingServer.VIEWPORT_ENVIRONMENT_ENABLED
	)


## The `Environment` this viewport's glow pass is running. Mutate it to drive the
## live pass; it is the shared `default_game_env.tres`, never a copy.
func get_environment_resource() -> Environment:
	var world_env := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	return world_env.environment if world_env != null else null
