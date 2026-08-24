extends GutTest

## Where an exported build starts (#577).
##
## [b]The decision is tested, not the jump.[/b] `OS.has_feature("release")` is
## false in the editor and false under GUT, and there is no way to make it true
## short of exporting — so driving [method Boot._ready] here would only ever
## exercise the no-op branch and would prove nothing about the case that matters.
## [method Boot.entry_scene] exists to make the choice a pure function of that
## one flag, which is the half that can actually be pinned.
##
## The other half of #577's acceptance — "there must be a working menu to boot
## into" — is asserted structurally at the bottom: the scene Boot names really is
## the frontmatter now, not the breadcrumb stack it hosted before #579.

const _BOOT := preload("res://autoload/boot.gd")
const _META_ROOT := preload("res://scenes/meta/meta_root.tscn")
const _FIRST_LEVEL := preload("res://scenes/first_level_sandbox.tscn")


func test_a_release_build_enters_the_menu() -> void:
	assert_eq(_BOOT.entry_scene(true), _META_ROOT)


func test_a_release_build_does_not_jump_straight_into_a_level() -> void:
	# The regression #577 exists for: the frontmatter was unreachable in the only
	# build a player ever sees.
	assert_ne(_BOOT.entry_scene(true), _FIRST_LEVEL)


func test_the_editor_is_left_alone() -> void:
	# Opening a sandbox scene from the editor has to land in that scene. A null
	# entry is what makes Boot a no-op rather than a redirect.
	assert_null(_BOOT.entry_scene(false))


func test_boot_did_not_redirect_this_test_run() -> void:
	# If the gate ever inverted, every GUT run would be fighting a scene change.
	# Cheap standing guard.
	#
	# Reached through the preloaded script rather than the `Boot` autoload
	# identifier, which does not exist: `project.godot` registers it as
	# `Boot="uid://…"` with no `*`, so the node is instantiated but never exposed
	# as a global. Naming it in a script is a PARSE error, which GUT reports by
	# skipping the whole file while still printing green.
	assert_false(OS.has_feature("release"), "GUT runs a debug build")
	assert_null(_BOOT.entry_scene(OS.has_feature("release")))


# --- there is a working menu to boot into ------------------------------------

func test_the_scene_boot_names_hosts_the_frontmatter() -> void:
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


## `Boot` was registered as `Boot="uid://…"` — the ONLY autoload in
## `project.godot` without the `*` prefix. Without it the script is still
## instantiated and still runs, so nothing visibly broke; it simply was not
## exposed as a global, and naming `Boot` in a script was a parse error.
##
## That is the worst shape a config defect can take here, because per
## `.claude/rules/testing.md` a parse error makes GUT **skip the whole file
## while still reporting green** — which is exactly what happened to the first
## draft of this file: it silently collected zero tests.
##
## So this asserts the registration itself, not just the behaviour. CLAUDE.md's
## autoload table calls `Boot` a singleton; this is what makes that true.
func test_boot_is_registered_as_a_real_global() -> void:
	assert_true(ProjectSettings.has_setting("autoload/Boot"), "Boot is registered")
	var entry: String = ProjectSettings.get_setting("autoload/Boot")
	assert_true(entry.begins_with("*"),
			"the * prefix is what exposes an autoload as a global — without it, "
			+ "naming Boot in a script is a parse error and GUT skips the file silently")
	assert_not_null(Engine.get_main_loop().root.get_node_or_null("Boot"),
			"and it is actually in the tree under that name")
