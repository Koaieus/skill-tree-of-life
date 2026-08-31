extends GutTest

## #670's "previewable in the VFX playground tab" acceptance item, pinned.
##
## The gallery's catalogues are the shopping list the eight per-spell units
## (#671-#678) read, so a stale entry there is worse than no gallery: a unit
## would compose a scene that no longer exists. These tests assert every listed
## path loads and every listed primitive actually fires.

const GALLERY := preload("res://addons/sandbox_host/tabs/20_vfx_primitives.gd")
const TAB := "res://addons/sandbox_host/tabs/20_vfx_tab.tscn"


func _gallery() -> VBoxContainer:
	var node := VBoxContainer.new()
	node.set_script(GALLERY)
	add_child_autofree(node)
	return node


func test_every_catalogued_visual_exists() -> void:
	for entry in GALLERY.VISUALS:
		var scene: PackedScene = load(entry[1])
		assert_not_null(scene, "%s (%s) must load" % [entry[0], entry[1]])


## A catalogue entry is either a `.gd` (a shape, built at its defaults) or a
## `.tres` (an authored tuning, previewed as authored — #684's bounce). Both
## must resolve to a [ProjectilePath]; nothing else belongs in the shopping list.
func test_every_catalogued_path_exists_and_is_a_projectile_path() -> void:
	for entry in GALLERY.PATHS:
		var res: Resource = load(entry[1])
		assert_not_null(res, "%s must load" % entry[1])
		var script := res as GDScript
		var path: ProjectilePath = script.new() if script != null else res as ProjectilePath
		assert_true(path is ProjectilePath, "%s must be a ProjectilePath" % entry[1])


## The gallery hands the ease picker whatever it builds, so an authored `.tres`
## entry MUST come back as a copy — the shipped `bounce_path.tres` is referenced
## live by the shared coordinator's fallback slot and by Reverberator's two path
## slots, and a sandbox dropdown must not retune all three for the session.
func test_an_authored_tres_entry_is_duplicated_not_handed_out_live() -> void:
	var gallery := _gallery()
	var found := 0
	for i in GALLERY.PATHS.size():
		var res_path: String = GALLERY.PATHS[i][1]
		if not res_path.ends_with(".tres"):
			continue
		found += 1
		var shared: ProjectilePath = load(res_path)
		gallery._path_picker = _picker_selecting(i)
		gallery._ease_picker = _picker_selecting(ProjectilePath.Ease.OUT_IN)
		var built: ProjectilePath = gallery._build_path()
		assert_ne(built, shared, "%s must be duplicated, never handed out live" % res_path)
		assert_eq(shared.ease_curve, ProjectilePath.Ease.LINEAR,
			"…so stamping the picker's ease leaves the shipped resource untouched")
	assert_gt(found, 0, "the catalogue must still carry its authored entry")


func _picker_selecting(index: int) -> OptionButton:
	var picker := OptionButton.new()
	for i in index + 1:
		picker.add_item("item %d" % i)
	picker.selected = index
	autofree(picker)
	return picker


func test_the_gallery_offers_all_five_primitives() -> void:
	var labels: String = ""
	for entry in GALLERY.VISUALS:
		labels += entry[0] + "\n"
	for entry in GALLERY.PATHS:
		labels += entry[0] + "\n"
	for needle in ["Bolt", "ImpactRing", "EdgeEnergize", "WavePath", "JitterPath", "Bounce"]:
		assert_true(labels.contains(needle), "the gallery must offer %s" % needle)


func test_the_ease_picker_matches_the_enum_it_drives() -> void:
	assert_eq(GALLERY.EASES.size(), ProjectilePath.Ease.size(),
		"a missing entry silently maps the picker onto the wrong curve")


func test_firing_every_visual_leaves_something_on_the_stage() -> void:
	var gallery := _gallery()
	for i in GALLERY.VISUALS.size():
		gallery._visual_picker.select(i)
		gallery._fire()
		var spawned: int = gallery._stage.get_child_count() - 2  # minus the two markers
		assert_gt(spawned, 0, "firing %s must put something on the stage" % GALLERY.VISUALS[i][0])


func test_firing_every_path_builds_a_configured_projectile_path() -> void:
	var gallery := _gallery()
	for i in GALLERY.PATHS.size():
		gallery._path_picker.select(i)
		for ease in GALLERY.EASES.size():
			gallery._ease_picker.select(ease)
			var path: ProjectilePath = gallery._build_path()
			assert_not_null(path, "%s must build" % GALLERY.PATHS[i][0])
			assert_eq(path.ease_curve, ease as ProjectilePath.Ease, "the ease picker must stick")


func test_the_tab_still_hosts_the_coordinator_playground() -> void:
	# The gallery is the tab's left column, not a replacement for it.
	var tab: Node = (load(TAB) as PackedScene).instantiate()
	add_child_autofree(tab)
	assert_not_null(tab.get_node_or_null(^"Layout/Split/PanelHost/PlaygroundPanel"),
		"the VFXCoordinator playground must still be the tab's main panel")
	assert_not_null(tab.get_node_or_null(^"Layout/Split/Sidebar/Primitives"),
		"and the primitive gallery must be its sidebar")
