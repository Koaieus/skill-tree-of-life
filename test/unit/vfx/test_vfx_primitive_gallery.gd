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


func test_every_catalogued_path_exists_and_is_a_projectile_path() -> void:
	for entry in GALLERY.PATHS:
		var script: GDScript = load(entry[1])
		assert_not_null(script, "%s must load" % entry[1])
		assert_true(script.new() is ProjectilePath, "%s must be a ProjectilePath" % entry[1])


func test_the_gallery_offers_all_five_primitives() -> void:
	var labels: String = ""
	for entry in GALLERY.VISUALS:
		labels += entry[0] + "\n"
	for entry in GALLERY.PATHS:
		labels += entry[0] + "\n"
	for needle in ["Bolt", "ImpactRing", "EdgeEnergize", "WavePath", "JitterPath"]:
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
