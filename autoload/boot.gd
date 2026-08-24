extends Node

## Release-build entry point: the one thing that decides where an exported game
## starts (#577).
##
## [b]In the editor this does nothing, on purpose.[/b] Opening
## `scenes/dev_sandbox.tscn` or any other sandbox from the editor has to land in
## that scene, not get redirected to the menu — so the whole behaviour is gated
## on `OS.has_feature("release")`, which is false in the editor and in tests.
##
## [b]An exported build starts in the menu.[/b] It used to jump straight into
## `first_level_sandbox`, which meant the frontmatter was unreachable in the only
## build a player ever sees. It also poked `preset.seed = 0` on the way past to
## get a random map; that is the lobby's job now — a blank seed field means
## "randomise me", [GameSession] resolves it exactly once, and the level reads
## the concrete value back. Reaching into a scene's procgen config from the boot
## path would be a second place that decides, and the wrong one.

const META_ROOT := preload("res://scenes/meta/meta_root.tscn")


func _ready() -> void:
	var entry := entry_scene(OS.has_feature("release"))
	if entry == null:
		return
	SceneDirector.goto(entry)


## Where a build of this kind starts, or `null` to leave the running scene
## alone.
##
## Split out as a pure function of the one input because
## `OS.has_feature("release")` cannot be made true from a test — asserting the
## DECISION is the only way to pin "a release build enters the menu" without an
## export, and an assertion that can only run in a build nobody tests is not an
## assertion. `test/unit/ui/test_boot_routing.gd` drives both branches.
static func entry_scene(is_release_build: bool) -> PackedScene:
	return META_ROOT if is_release_build else null
