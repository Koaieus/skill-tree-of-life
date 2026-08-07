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


## The `Environment` this viewport's glow pass is running. Mutate it to drive the
## live pass; it is the shared `default_game_env.tres`, never a copy.
func get_environment_resource() -> Environment:
	var world_env := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	return world_env.environment if world_env != null else null
