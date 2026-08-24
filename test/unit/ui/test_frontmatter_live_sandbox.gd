extends GutTest

## #578 — the frontmatter live tab.
##
## Nothing here judges how the menu LOOKS; #567's testing contract puts glow,
## easing and "is it good" on the owner's eye, and this tab is what puts them
## there. What IS machine-checkable is the two ways this unit can be wrong in a
## way nobody notices for a month:
##
## 1. **The tab is composed the way `.claude/rules/sandbox-host.md` requires** —
##    an inherited scene of `sandbox_live_tab.tscn` with its panel INSTANCED
##    inside it under `%PanelHost`, never injected through the legacy
##    `panel_scene` export. Both forms run; only one previews and reloads
##    correctly, so the difference is invisible until it bites.
## 2. **The bench is the shipped scene, not a mock.** That is the #309 lesson —
##    the tooltip fan's first live tab drove a hand-rolled copy of the fan's
##    layout and drifted. A test that names `frontmatter_root.tscn` is what
##    stops the same thing happening twice.
##
## The knob assertions then say the control column is really wired to the live
## objects, which is #578's "visibly affects the running menu" in the half a
## headless run can see.

const _TAB := preload("res://addons/sandbox_host/tabs/85_frontmatter_tab.tscn")
const _PANEL := preload("res://ui/frontmatter/frontmatter_live_sandbox.tscn")
const _PANEL_SCRIPT := preload("res://ui/frontmatter/frontmatter_live_sandbox.gd")

const _ROOT_PATH := "res://ui/frontmatter/frontmatter_root.tscn"

var _panel: Control


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)


## The six ratios are `static var` now — process-global. A test that left one
## tuned would silently re-pose every menu built afterwards IN THIS SAME RUN,
## including `test_frontmatter_layout.gd` and `test_hover_preview.gd`, and the
## failure would land on them rather than here. The panel resets on teardown
## too; this is the belt to that braces.
func after_each() -> void:
	FrontmatterLayout.reset_geometry()


func _frontmatter() -> FrontmatterRoot:
	return _panel.get_node("%Frontmatter") as FrontmatterRoot


func _knobs() -> VBoxContainer:
	return _panel.get_node("%Knobs") as VBoxContainer


## Every slider/check in the control column, whatever container it was nested in.
func _controls_of(type: String) -> Array[Node]:
	return _knobs().find_children("*", type, true, false)


# --- the tab is composed the way the rule requires ---------------------------

func test_the_tab_is_an_inherited_scene_of_the_live_tab_base() -> void:
	var tab: SandboxLiveTab = _TAB.instantiate()
	add_child_autofree(tab)
	assert_true(tab is SandboxLiveTab, "a live tab, not a played one")
	assert_eq(tab.get_mode(), SandboxTab.Mode.LIVE_EDIT)
	assert_eq(tab.get_tab_title(), "Frontmatter")
	assert_eq(tab.tab_id, &"frontmatter")
	assert_not_null(tab.get_node_or_null("%PanelHost"), "it carries the base's chrome")


## The trap the rule exists to prevent: `panel_scene` still works, and a tab
## using it looks identical until it fails to preview or to reload.
func test_the_panel_is_instanced_inside_the_tab_not_injected() -> void:
	var tab: SandboxLiveTab = _TAB.instantiate()
	add_child_autofree(tab)
	assert_null(tab.panel_scene, "the legacy panel_scene export is NOT used")
	var host := tab.get_node("%PanelHost")
	var baked: Control = null
	for child in host.get_children():
		if child is Control:
			baked = child as Control
			break
	assert_not_null(baked, "the panel is authored inside the tab, under %PanelHost")
	assert_eq(baked.get_script(), _PANEL_SCRIPT, "and it is this unit's panel")


func test_the_tab_answers_the_loader_contract() -> void:
	var tab: SandboxLiveTab = _TAB.instantiate()
	add_child_autofree(tab)
	assert_eq(tab.loader_method, &"noop")
	# There is no inspected resource to route; the call must simply not throw.
	tab.load_object(null)
	assert_true(_panel.has_method(tab.loader_method), "the panel answers it")


# --- it benches the shipped scene --------------------------------------------

func test_the_bench_is_the_real_frontmatter_scene() -> void:
	var root := _frontmatter()
	assert_not_null(root, "the bench exists")
	assert_eq(root.scene_file_path, _ROOT_PATH, "the SHIPPED scene, not a mock (#309)")
	assert_not_null(root.tree, "and it built itself")
	assert_eq(root.focus_id, root.tree.root, "parked on the root, as a cold boot leaves it")


## Glow is one WorldEnvironment pass PER VIEWPORT, and meta_root's does not
## reach a SubViewport mounted here — so without this the tab would be judging
## a picture with every Emissive tier rendered flat.
func test_the_bench_sits_in_a_viewport_that_can_glow() -> void:
	var viewport := _frontmatter().get_viewport()
	assert_true(viewport is SubViewport, "benched in its own viewport")
	assert_true((viewport as SubViewport).use_hdr_2d, "HDR, or nothing can exceed 1.0")
	var env: WorldEnvironment = null
	for child in viewport.get_children():
		if child is WorldEnvironment:
			env = child as WorldEnvironment
			break
	assert_not_null(env, "with its own glow pass")
	assert_true(env.environment.glow_enabled, "which is actually on")


# --- the control column is wired to the live objects -------------------------

func test_there_is_a_navigation_button_for_every_menu_node() -> void:
	var labels: Array[String] = []
	for button: Node in _controls_of("Button"):
		labels.append((button as Button).text)
	for id in _frontmatter().tree.ids():
		assert_true(labels.has(String(id)), "%s is one click away" % id)


func test_the_hover_picker_offers_every_node_plus_none() -> void:
	var pickers := _controls_of("OptionButton")
	assert_eq(pickers.size(), 1, "one hover source")
	var picker := pickers[0] as OptionButton
	assert_eq(picker.item_count, _frontmatter().tree.size() + 1, "every node, plus (none)")
	assert_eq(picker.get_item_metadata(0), &"", "the first entry clears the hover")


## The acceptance's "visibly affects the running menu", in the half a headless
## run can see: a knob change really does reach the live objects.
func test_a_knob_change_reaches_the_live_objects() -> void:
	_panel._values[_PANEL_SCRIPT.K_NODE_RADIUS] = 48.0
	_panel._values[_PANEL_SCRIPT.K_EDGE_UNLIT_ALPHA] = 0.2
	_panel._values[_PANEL_SCRIPT.K_TRAVEL] = 0.25
	_panel._values[_PANEL_SCRIPT.K_PEEK_ALPHA] = 0.8
	_panel._apply_all()

	var root := _frontmatter()
	assert_almost_eq(root.travel_duration, 0.25, 0.0001)
	assert_almost_eq(root.view_for(MenuGraph.ID_EXIT).radius, 48.0, 0.0001)
	assert_almost_eq(root.edge_for(MenuGraph.ID_EXIT).unlit_alpha, 0.2, 0.0001)
	assert_almost_eq(
		(root.get_node("%HoverPreview") as HoverPreview).preview_alpha, 0.8, 0.0001
	)


## Every widget the column tunes is really there, and the knobs really land on
## it. Unguarded on purpose: #572's affordance was eaten by the shell's
## `_clear()` and a tolerant lookup would have kept hiding it.
func test_every_widget_the_column_tunes_is_reachable() -> void:
	_panel._values[_PANEL_SCRIPT.K_BACK_REST] = Emissive.ALERT
	_panel._values[_PANEL_SCRIPT.K_BACK_HOVER] = Emissive.PEAK
	_panel._values[_PANEL_SCRIPT.K_TOOLTIP_SCALE] = 0.7
	_panel._apply_all()

	var root := _frontmatter()
	var back := root.get_node_or_null("%BackAffordance") as BackAffordance
	assert_not_null(back, "the affordance survives build() (#572)")
	assert_almost_eq(back.rest_stops, Emissive.ALERT, 0.0001)
	assert_almost_eq(back.hover_stops, Emissive.PEAK, 0.0001)

	var tooltip: MenuTooltip = null
	for child in root.get_node("%PanelLayer").get_children():
		if child is MenuTooltip:
			tooltip = child as MenuTooltip
	assert_not_null(tooltip, "the tooltip is minted by build()")
	assert_almost_eq(tooltip.start_scale, 0.7, 0.0001)


## The tab rebuilds in place on every geometry knob, which is the path that
## found #572. A widget must survive that too, not just the first build.
func test_the_widgets_survive_a_rebuild() -> void:
	_panel._rebuild()
	_panel._rebuild()
	var root := _frontmatter()
	assert_not_null(root.get_node_or_null("%BackAffordance"), "still there after two rebuilds")
	assert_not_null(root.get_node_or_null("%HoverPreview"))


## FrontmatterRoot.build() is idempotent so the tab can rebuild in place — but a
## rebuild mints fresh views, so the tuning only survives because this panel
## holds it and pushes it again.
func test_a_rebuild_keeps_the_tuning() -> void:
	_panel._values[_PANEL_SCRIPT.K_NODE_RADIUS] = 12.0
	_panel._apply_all()
	_panel._rebuild()
	var root := _frontmatter()
	assert_eq(root.focus_id, root.tree.root, "a real cold boot")
	for id in root.tree.ids():
		assert_almost_eq(
			root.view_for(id).radius, 12.0, 0.0001, "%s kept the tuned radius" % id
		)


## Defaults must match what the shipped scenes already carry, or merely opening
## the tab would retune the menu and the first look would be a lie.
func test_the_defaults_change_nothing_on_open() -> void:
	var root := _frontmatter()
	var fresh: FrontmatterRoot = load(_ROOT_PATH).instantiate()
	add_child_autofree(fresh)
	assert_almost_eq(root.travel_duration, fresh.travel_duration, 0.0001)
	assert_almost_eq(
		root.view_for(MenuGraph.ID_ROOT).radius, fresh.view_for(MenuGraph.ID_ROOT).radius, 0.0001
	)
	assert_almost_eq(
		root.edge_for(MenuGraph.ID_EXIT).unlit_alpha,
		fresh.edge_for(MenuGraph.ID_EXIT).unlit_alpha,
		0.0001,
	)
	assert_almost_eq(
		(root.get_node("%HoverPreview") as HoverPreview).preview_alpha,
		HoverPreview.DEFAULT_PREVIEW_ALPHA,
		0.0001,
	)


# --- the geometry knobs -------------------------------------------------------

## The panel's defaults must BE the authored ratios, or merely opening the tab
## would retune the menu — and since the sliders are authored in design px and
## the solver stores fractions, this is also where a units mistake surfaces.
func test_the_geometry_defaults_are_the_authored_ratios() -> void:
	FrontmatterLayout.reset_geometry()
	var design := FrontmatterLayout.DESIGN_VIEWPORT
	var expected := {
		_PANEL_SCRIPT.K_HERO_X: FrontmatterLayout.HERO_SLOT_RATIO.x * design.x,
		_PANEL_SCRIPT.K_HERO_Y: FrontmatterLayout.HERO_SLOT_RATIO.y * design.y,
		_PANEL_SCRIPT.K_COLUMN_STEP: FrontmatterLayout.COLUMN_STEP_RATIO * design.x,
		_PANEL_SCRIPT.K_SIBLING_GAP: FrontmatterLayout.SIBLING_GAP_RATIO * design.y,
		_PANEL_SCRIPT.K_PREVIEW_COLUMN: FrontmatterLayout.PREVIEW_COLUMN_RATIO * design.x,
		_PANEL_SCRIPT.K_PREVIEW_GAP: FrontmatterLayout.PREVIEW_GAP_RATIO * design.y,
		_PANEL_SCRIPT.K_PREVIEW_SCALE: FrontmatterLayout.PREVIEW_SCALE,
	}
	for key: StringName in _PANEL_SCRIPT.GEOMETRY_KEYS:
		assert_true(expected.has(key), "%s is covered by this test" % key)
		assert_almost_eq(
			_PANEL_SCRIPT.DEFAULTS[key] as float, expected[key] as float, 0.001,
			"default for %s" % key,
		)


## #578's headline acceptance, in the half a headless run can see: a geometry
## knob really does re-pose the running menu.
func test_a_geometry_knob_re_poses_the_running_menu() -> void:
	var root := _frontmatter()
	var before := _column_step_of(root)
	assert_almost_eq(before, 306.0, 0.001, "the authored column step, in world units")

	_panel._values[_PANEL_SCRIPT.K_COLUMN_STEP] = 500.0
	_panel._rebuild()
	assert_almost_eq(_column_step_of(_frontmatter()), 500.0, 0.001, "the menu moved")
	assert_almost_eq(
		FrontmatterLayout.COLUMN_STEP_RATIO,
		500.0 / FrontmatterLayout.DESIGN_VIEWPORT.x,
		0.0001,
		"and it is stored as a ratio, not as a pixel count",
	)


func test_the_preview_knobs_reach_the_collapsed_slots() -> void:
	_panel._values[_PANEL_SCRIPT.K_PREVIEW_COLUMN] = 400.0
	_panel._values[_PANEL_SCRIPT.K_PREVIEW_SCALE] = 0.8
	_panel._rebuild()
	var root := _frontmatter()
	var slots := FrontmatterLayout.preview_slots(root.tree, MenuGraph.ID_SINGLE_PLAYER)
	var parent: Vector2 = FrontmatterLayout.solve(root.tree)[MenuGraph.ID_SINGLE_PLAYER]
	for child_id: StringName in slots:
		assert_almost_eq(
			(slots[child_id] as Vector2).x - parent.x, 400.0, 0.001,
			"%s peeks at the tuned offset" % child_id,
		)
		assert_almost_eq(
			root.view_for(child_id).scale.x, 0.8, 0.001, "%s draws at the tuned scale" % child_id
		)


func test_reset_geometry_puts_the_menu_back() -> void:
	var before := _poses()
	_panel._values[_PANEL_SCRIPT.K_COLUMN_STEP] = 500.0
	_panel._values[_PANEL_SCRIPT.K_SIBLING_GAP] = 300.0
	_panel._rebuild()
	assert_ne(_poses(), before, "the tuning did something")
	_panel._reset_geometry()
	assert_eq(_poses(), before, "and reset put all of it back")
	for key: StringName in _PANEL_SCRIPT.GEOMETRY_KEYS:
		assert_almost_eq(
			_panel._values[key] as float, _PANEL_SCRIPT.DEFAULTS[key] as float, 0.001,
			"%s is back to its default" % key,
		)


## The ratios outlive the panel, so the panel has to hand them back. Without
## this, one sandbox session re-poses every menu built later in the process.
func test_tearing_the_panel_down_hands_the_ratios_back() -> void:
	_panel._values[_PANEL_SCRIPT.K_SIBLING_GAP] = 350.0
	_panel._rebuild()
	assert_ne(FrontmatterLayout.SIBLING_GAP_RATIO, 132.0 / 900.0, "tuned")
	_panel.get_parent().remove_child(_panel)
	assert_almost_eq(
		FrontmatterLayout.SIBLING_GAP_RATIO, 132.0 / 900.0, 0.0001,
		"teardown restored the authored ratio",
	)


func test_the_geometry_readout_quotes_the_live_ratios() -> void:
	_panel._values[_PANEL_SCRIPT.K_PREVIEW_GAP] = 90.0
	_panel._rebuild()
	var text := ""
	for label: Node in _controls_of("Label"):
		if (label as Label).text.contains("PREVIEW_GAP_RATIO"):
			text = (label as Label).text
	assert_ne(text, "", "the read-out exists")
	assert_true(
		text.contains("%.4f" % (90.0 / FrontmatterLayout.DESIGN_VIEWPORT.y)),
		"and shows what the solver is actually holding",
	)


## World-space distance from the root to its children, which is what
## COLUMN_STEP_RATIO buys at zoom 1.
func _column_step_of(root: FrontmatterRoot) -> float:
	return root.view_for(MenuGraph.ID_SINGLE_PLAYER).position.x - root.view_for(root.tree.root).position.x


## An ARRAY, so one assert_eq really does compare every node.
func _poses() -> Array:
	var out: Array = []
	var root := _frontmatter()
	for id in root.tree.ids():
		var view := root.view_for(id)
		out.append([id, view.position, view.scale])
	return out
