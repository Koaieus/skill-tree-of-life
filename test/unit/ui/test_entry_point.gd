extends GutTest

## Where a build starts (#577), and that there is a working menu to start in.
##
## [b]The entry point is `run/main_scene`, not a runtime redirect.[/b] It used
## to be a `Boot` autoload that read `OS.has_feature("release")` and jumped to
## the menu via [code]SceneDirector.goto[/code] — but the engine instantiates
## `main_scene` before any autoload can intervene, so an exported build built a
## whole sandbox level (graph, entities, HUD compose), showed it for the length
## of a fade plus a threaded load, and threw it away. No redirect can be
## flash-free; the entry point has to be right in the config.
##
## So the decision is now a project setting, and this asserts that setting.

const _META_ROOT_PATH := "res://scenes/meta/meta_root.tscn"
const _META_ROOT := preload("res://scenes/meta/meta_root.tscn")
const _FIRST_LEVEL_PATH := "res://scenes/first_level_sandbox.tscn"
const _DEV_SANDBOX_PATH := "res://scenes/dev_sandbox.tscn"


func _main_scene_path() -> String:
	# The setting is stored as a `uid://…`, which is stable across moves but is
	# not comparable to a path by eye.
	var setting: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_false(setting.is_empty(), "the project declares a main scene")
	return ResourceUID.uid_to_path(setting) if setting.begins_with("uid://") else setting


func test_a_build_enters_the_menu() -> void:
	assert_eq(_main_scene_path(), _META_ROOT_PATH)


func test_a_build_does_not_start_in_a_level_or_a_sandbox() -> void:
	# The regression #577 exists for: the frontmatter was unreachable in the only
	# build a player ever sees. And the one this file was rewritten for: booting
	# into `dev_sandbox` and cutting away to the menu a moment later.
	var path := _main_scene_path()
	assert_ne(path, _FIRST_LEVEL_PATH)
	assert_ne(path, _DEV_SANDBOX_PATH)


func test_nothing_redirects_the_entry_scene_any_more() -> void:
	# `Boot` is gone; if it (or a successor) ever comes back as an autoload that
	# routes on _ready, the flash comes back with it.
	assert_false(ProjectSettings.has_setting("autoload/Boot"),
			"the entry point lives in run/main_scene, not in an autoload")


# --- there is a working menu to boot into ------------------------------------

func test_the_main_scene_hosts_the_frontmatter() -> void:
	# #577 was re-pointed to block on the cutover rather than on the panel layer
	# precisely because this assertion was meaningless while `meta_root.tscn`
	# still hosted the old stack. It is not meaningless now.
	var meta: Control = _META_ROOT.instantiate()
	add_child_autofree(meta)

	var frontmatter := meta.get_node_or_null("%Frontmatter")
	assert_not_null(frontmatter, "meta_root hosts the menu graph")
	assert_true(frontmatter is FrontmatterRoot)


func test_the_menu_it_boots_into_starts_on_the_attract_state() -> void:
	# A player opening the game gets the splash, not a tree they never chose to
	# expand — and the splash is the root node zoomed, so the menu is already
	# built behind it (#574).
	var meta: Control = _META_ROOT.instantiate()
	add_child_autofree(meta)

	var splash := meta.get_node_or_null("%Splash") as SplashScreen
	assert_not_null(splash, "meta_root hosts the attract state")
	assert_false(splash.is_advanced(), "a cold start has not advanced")

	var frontmatter := meta.get_node("%Frontmatter") as FrontmatterRoot
	assert_eq(frontmatter.focus_id, frontmatter.tree.root,
			"the tree is built and parked on its root")
