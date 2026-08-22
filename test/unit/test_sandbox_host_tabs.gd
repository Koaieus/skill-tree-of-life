extends GutTest
## Lints the auto-discovered sandbox host tab scenes (#77): every tab .tscn must
## load, root as a SandboxTab, with its exported config resolved non-null.
## Hand/generator-authored .tscn can silently null an @export (uid mismatch /
## field strip — see .claude/rules/godot-workflow.md); this is the guard the
## rule prescribes ("load the preset and assert every field is non-null").

const _TABS_DIR := "res://addons/sandbox_host/tabs/"

var _params := _tab_files()


static func _tab_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(_TABS_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".tscn"):
				out.append(f)
	out.sort()
	return out


func test_tabs_dir_is_non_empty() -> void:
	assert_gt(_tab_files().size(), 0, "expected tab scenes under %s" % _TABS_DIR)


func test_tab_scene_exports_resolve(p = use_parameters(_params)) -> void:
	var scene: PackedScene = load(_TABS_DIR + p)
	assert_not_null(scene, "%s failed to load" % p)
	var tab = scene.instantiate()
	assert_true(tab is SandboxTab, "%s root must extend SandboxTab" % p)
	assert_ne(tab.get_tab_title(), "", "%s has empty tab_title" % p)

	if tab.get_mode() == SandboxTab.Mode.LIVE_EDIT:
		assert_ne(tab.tab_id, &"", "%s (live) has empty tab_id" % p)
		# Baked tabs (.claude/rules/sandbox-host.md) instance their panel inside
		# %PanelHost and carry no panel_scene; legacy tabs still inject via the export.
		var panel_host: Node = tab.get_node_or_null(^"%PanelHost")
		var is_baked := panel_host != null and panel_host.get_child_count() > 0
		assert_true(tab.panel_scene != null or is_baked,
			"%s (live) has null panel_scene and no baked %%PanelHost child" % p)
		assert_ne(tab.loader_method, &"", "%s (live) has empty loader_method" % p)
	else:
		assert_ne(tab.scene_path, "", "%s (played) has empty scene_path" % p)
		assert_true(ResourceLoader.exists(tab.scene_path),
			"%s (played) scene_path missing on disk: %s" % [p, tab.scene_path])

	tab.free()


func test_host_scene_loads() -> void:
	var host_scene: PackedScene = load("res://addons/sandbox_host/sandbox_host.tscn")
	assert_not_null(host_scene, "sandbox_host.tscn failed to load")
	var host = host_scene.instantiate()
	assert_true(host is SandboxHost, "host root must be a SandboxHost")
	assert_not_null(host.get_node_or_null("Tabs"), "host must carry its Tabs TabContainer")
	host.free()


# ── Editor-hint lint ─────────────────────────────────────────────────────────

## A live tab builds its world with `sandbox_world.gd`, which instantiates
## RUNTIME, non-`@tool` scripts from tool code. Godot runs those normally — they
## are not part of an edited scene — but with `Engine.is_editor_hint()` TRUE. So
## a script that opens `_ready` with a bare
##
##     if Engine.is_editor_hint():
##         return
##
## is half-built in every live tab: it answers method calls while every signal
## subscription below the guard is silently absent. That is how #466's reform
## slot shipped dead in the melee tab — the capture hangs off `attack_launched`,
## subscribed under that guard, so `can_reform()` could never be true there.
##
## [b]This is a LINT because no runtime assertion can see it.[/b] GUT is
## headless, `is_editor_hint()` is false, the guard never fires, and any test —
## including one asserting the subscription itself — passes for the wrong
## reason. Reading the source is the only check that goes red on a revert.
##
## The fix a failure asks for is never "delete the guard": it is to move it onto
## the individual lines that reach for the OS or the edited scene (an
## `_unhandled_input`, an `Input.set_default_cursor_shape`, a subscription to a
## node's own physics pick), each with its reason. See
## `docs/domain/sandbox-framework.md`.
const _SANDBOX_WORLD_PATH := "res://scenes/dev/sandbox_world.gd"

var _world_scripts := _scripts_a_live_tab_instantiates()


## Every `res://…gd` a live tab's scaffold preloads, read off its source so a
## system added to `sandbox_world.gd` is linted without touching this file.
static func _scripts_a_live_tab_instantiates() -> Array:
	var out: Array = []
	var re := RegEx.create_from_string('preload\\("(res://[^"]+\\.gd)"\\)')
	for m in re.search_all(FileAccess.get_file_as_string(_SANDBOX_WORLD_PATH)):
		out.append(m.get_string(1))
	out.sort()
	return out


func test_the_scaffold_still_names_its_scripts() -> void:
	assert_gt(_world_scripts.size(), 0,
			"the lint below is vacuous if no script path was parsed out of %s"
			% _SANDBOX_WORLD_PATH)


func test_no_live_tab_system_blanket_guards_ready_on_the_editor_hint(
		p = use_parameters(_world_scripts)) -> void:
	var src := FileAccess.get_file_as_string(p)
	var at := src.find("func _ready(")
	if at < 0:
		return
	var body := src.substr(at)
	var ends_at := body.find("\nfunc ")
	if ends_at > 0:
		body = body.substr(0, ends_at)
	assert_false(body.contains("if Engine.is_editor_hint():\n\t\treturn"),
			("%s guards its whole _ready on the editor hint, so a live sandbox tab "
			+ "gets an object that answers calls with none of its subscriptions — "
			+ "guard the OS-facing lines instead (docs/domain/sandbox-framework.md)")
			% p)
