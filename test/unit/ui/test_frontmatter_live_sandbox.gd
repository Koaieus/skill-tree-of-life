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


## `PREVIEW_SCALE` and the live per-fan overrides are process-global. A test that
## left one tuned would silently re-pose every menu built afterwards IN THIS SAME
## RUN, including `test_frontmatter_layout.gd` and `test_hover_preview.gd`, and
## the failure would land on them rather than here. #590 shrank that hazard from
## six knobs to these; it did not remove it. The panel resets on teardown too;
## this is the belt to that braces.
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
	var picker := _panel._hover_picker as OptionButton
	assert_not_null(picker, "one hover source")
	assert_eq(picker.item_count, _frontmatter().tree.size() + 1, "every node, plus (none)")
	assert_eq(picker.get_item_metadata(0), &"", "the first entry clears the hover")


## The acceptance's "visibly affects the running menu", in the half a headless
## run can see: a knob change really does reach the live objects.
func test_a_knob_change_reaches_the_live_objects() -> void:
	_panel._values[_PANEL_SCRIPT.K_EDGE_UNLIT_ALPHA] = 0.2
	_panel._values[_PANEL_SCRIPT.K_TRAVEL] = 0.25
	_panel._values[_PANEL_SCRIPT.K_PEEK_ALPHA] = 0.8
	_panel._apply_all()

	var root := _frontmatter()
	assert_almost_eq(root.travel_duration, 0.25, 0.0001)
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
	_panel._values[_PANEL_SCRIPT.K_EDGE_UNLIT_ALPHA] = 0.12
	_panel._apply_all()
	_panel._rebuild()
	var root := _frontmatter()
	assert_eq(root.focus_id, root.tree.root, "a real cold boot")
	for id in root.tree.ids():
		if id == root.tree.root:
			continue  # the root is nobody's child, so it has no edge
		assert_almost_eq(
			root.edge_for(id).unlit_alpha, 0.12, 0.0001, "%s kept the tuned alpha" % id
		)


## Defaults must match what the shipped scenes already carry, or merely opening
## the tab would retune the menu and the first look would be a lie.
##
## [b]This test is why the node-radius knob is gone[/b] (#593). It was a single
## GLOBAL radius written over every view at `DEFAULTS`' 32, so the moment
## `root_menu.tscn` authored a bigger root, opening the tab shrank it — a live
## defect, caught here. Radius is authored geometry now (#591), so the tab does
## not write it at all and this asserts the stronger thing: the AUTHORED radius,
## per node, is exactly what a fresh menu has.
func test_the_defaults_change_nothing_on_open() -> void:
	var root := _frontmatter()
	var fresh: FrontmatterRoot = load(_ROOT_PATH).instantiate()
	add_child_autofree(fresh)
	assert_almost_eq(root.travel_duration, fresh.travel_duration, 0.0001)
	for id in root.tree.ids():
		var authored: float = FrontmatterLayout.look_of(id).radius
		assert_almost_eq(root.view_for(id).radius, authored, 0.0001,
				"'%s' is still the size its slot authors" % id)
		assert_almost_eq(fresh.view_for(id).radius, authored, 0.0001,
				"'%s' agrees with a menu the tab never touched" % id)
	assert_gt(FrontmatterLayout.look_of(MenuGraph.ID_ROOT).radius,
			FrontmatterLayout.look_of(MenuGraph.ID_EXIT).radius,
			"and the root is the bigger one, which the old global knob flattened")
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

## The panel's defaults must BE what the code and the scenes already carry, or
## merely opening the tab would retune the menu.
##
## Re-pointed by #594. Five of the six ratios died with the recursion (#590), so
## what is pinned now is the one surviving constant plus the rule that replaced
## the other five: the per-fan knobs are NOT literals in this panel at all, they
## are read out of `ui/frontmatter/layout/` — which is the only way a reset can
## be guaranteed to agree with the scene an author is editing.
func test_the_geometry_defaults_are_the_authored_values() -> void:
	FrontmatterLayout.reset_geometry()
	assert_almost_eq(
		_PANEL_SCRIPT.DEFAULTS[_PANEL_SCRIPT.K_PREVIEW_SCALE] as float,
		FrontmatterLayout.PREVIEW_SCALE, 0.0001, "default for preview_scale",
	)
	for key: StringName in _PANEL_SCRIPT.GEOMETRY_KEYS:
		if key == _PANEL_SCRIPT.K_PREVIEW_SCALE:
			continue
		assert_false(_PANEL_SCRIPT.DEFAULTS.has(key),
				"%s is read off the fan's scene, never copied into DEFAULTS" % key)

	var authored := FrontmatterLayout.authored_fan_theme(&"root")
	assert_almost_eq(
		_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] as float,
		authored[&"separation"] as float, 0.001,
		"the panel opens on what root_menu.tscn authors",
	)


## #578's headline acceptance, in the half a headless run can see: a geometry
## knob really does re-pose the running menu. Re-pointed by #594 from the dead
## `COLUMN_STEP_RATIO` onto the selected fan's authored separation.
func test_a_geometry_knob_re_poses_the_running_menu() -> void:
	var root := _frontmatter()
	assert_almost_eq(_fan_pitch(root, MenuGraph.ID_ROOT), 190.0, 0.001,
			"root_menu.tscn's authored top gap, in world units")

	_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] = 60.0
	_panel._rebuild()
	assert_almost_eq(_fan_pitch(_frontmatter(), MenuGraph.ID_ROOT), 250.0, 0.001,
			"separation lands ON TOP of the authored slot heights")


## Selecting a fan points the sliders at THAT fan, and tuning one leaves its
## neighbours alone — the whole reason authoring replaced a global pitch.
func test_the_fan_picker_tunes_one_fan_at_a_time() -> void:
	# Solved homes, not view positions: MULTIPLAYER's children are collapsed onto
	# their parent while the menu is parked on the root, so the pose a view is at
	# is the peek-ahead pitch rather than the fan's own.
	var tree := _frontmatter().tree
	var before_mp := _solved_pitch(tree, MenuGraph.ID_MULTIPLAYER)
	assert_almost_eq(before_mp, 110.0, 0.001, "multiplayer_menu.tscn's authored pitch")

	_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] = 60.0
	_panel._rebuild()
	assert_almost_eq(_solved_pitch(tree, MenuGraph.ID_MULTIPLAYER), before_mp, 0.001,
			"MULTIPLAYER's fan did not move when the root fan was tuned")

	_panel._selected_fan = MenuGraph.ID_MULTIPLAYER
	_panel._load_authored_fan_values()
	_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] = 40.0
	_panel._rebuild()
	assert_almost_eq(_solved_pitch(tree, MenuGraph.ID_MULTIPLAYER), before_mp + 40.0,
			0.001, "and now it does")


func test_the_preview_scale_knob_reaches_the_collapsed_nodes() -> void:
	_panel._values[_PANEL_SCRIPT.K_PREVIEW_SCALE] = 0.8
	_panel._rebuild()
	var root := _frontmatter()
	for child_id in root.tree.children_of(MenuGraph.ID_SINGLE_PLAYER):
		assert_almost_eq(
			root.view_for(child_id).scale.x, 0.8, 0.001, "%s draws at the tuned scale" % child_id
		)


## #594: `hidden_alpha` is the owner's "visible when possible" idea, surfaced so
## it can be judged by eye. It is an alpha, not a position, so it must land
## WITHOUT a rebuild — a rebuild would re-park the camera and lose the look.
func test_ghosting_the_tree_in_needs_no_rebuild() -> void:
	var root := _frontmatter()
	var far: MenuNodeView = root.view_for(MenuGraph.ID_JOIN)
	assert_almost_eq(far.modulate.a, HoverPreview.DEFAULT_HIDDEN_ALPHA, 0.001,
			"a collapsed node is invisible at the authored default")

	_panel._values[_PANEL_SCRIPT.K_PEEK_HIDDEN] = 0.6
	_panel._apply_all()
	assert_true(far == _frontmatter().view_for(MenuGraph.ID_JOIN),
			"the same view, not a rebuild")
	assert_almost_eq(far.modulate.a, 0.6, 0.001, "and the whole tree ghosted in")


## Every knob this panel writes is handed back by `reset_geometry()`, one at a
## time — the acceptance that stops a knob being added to `_apply_geometry` and
## forgotten in the reset path.
func test_every_geometry_knob_is_restored_by_reset() -> void:
	for key: StringName in _PANEL_SCRIPT.GEOMETRY_KEYS:
		var authored: float = _panel._values[key]
		_panel._values[key] = authored + (0.3 if key == _PANEL_SCRIPT.K_PREVIEW_SCALE else 37.0)
		_panel._rebuild()
		_panel._reset_geometry()
		assert_almost_eq(_panel._values[key] as float, authored, 0.001,
				"%s is back to its authored value" % key)


func test_reset_geometry_puts_the_menu_back() -> void:
	var before := _poses()
	_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] = 70.0
	_panel._values[_PANEL_SCRIPT.K_PREVIEW_SCALE] = 0.9
	_panel._rebuild()
	assert_ne(_poses(), before, "the tuning did something")
	_panel._reset_geometry()
	assert_eq(_poses(), before, "and reset put all of it back")
	assert_almost_eq(
		_panel._values[_PANEL_SCRIPT.K_PREVIEW_SCALE] as float,
		_PANEL_SCRIPT.DEFAULTS[_PANEL_SCRIPT.K_PREVIEW_SCALE] as float, 0.001,
	)


## The overrides outlive the panel, so the panel has to hand them back. Without
## this, one sandbox session re-poses every menu built later in the process.
func test_tearing_the_panel_down_hands_the_geometry_back() -> void:
	var authored := _fan_pitch(_frontmatter(), MenuGraph.ID_ROOT)
	_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] = 90.0
	_panel._values[_PANEL_SCRIPT.K_PREVIEW_SCALE] = 0.9
	_panel._rebuild()
	assert_ne(FrontmatterLayout.PREVIEW_SCALE, 0.42, "tuned")

	_panel.get_parent().remove_child(_panel)
	assert_almost_eq(FrontmatterLayout.PREVIEW_SCALE, 0.42, 0.0001,
			"teardown restored the surviving constant")
	var tree := MenuGraph.build()
	var positions := FrontmatterLayout.solve(tree)
	var options := tree.children_of(MenuGraph.ID_ROOT)
	assert_almost_eq(
		(positions[options[1]] as Vector2).y - (positions[options[0]] as Vector2).y,
		authored, 0.001, "and dropped the fan override",
	)


func test_the_geometry_readout_quotes_the_live_geometry() -> void:
	_panel._values[_PANEL_SCRIPT.K_FAN_SEPARATION] = 55.0
	_panel._rebuild()
	var text := ""
	for label: Node in _controls_of("Label"):
		if (label as Label).text.contains("column_step()"):
			text = (label as Label).text
	assert_ne(text, "", "the read-out exists")
	assert_true(text.contains("55.0"), "and shows the separation the solver is holding")
	assert_true(text.contains("%.1f" % (190.0 + 55.0)),
			"and the pitch that separation actually bought")


## The pitch [param parent]'s fan spaces its children at, measured on the built
## menu — which is what an author is judging when they drag `separation`. Only
## honest for a fan that is GROWN OUT: a collapsed one is stacked on its parent
## at the peek-ahead pitch, so use [method _solved_pitch] for those.
func _fan_pitch(root: FrontmatterRoot, parent: StringName) -> float:
	var children := root.tree.children_of(parent)
	return root.view_for(children[1]).position.y - root.view_for(children[0]).position.y


## The same pitch, taken from the solver's homes rather than from where a view
## currently rests.
func _solved_pitch(tree: MenuGraph, parent: StringName) -> float:
	var positions := FrontmatterLayout.solve(tree)
	var children := tree.children_of(parent)
	return (positions[children[1]] as Vector2).y - (positions[children[0]] as Vector2).y


## An ARRAY, so one assert_eq really does compare every node.
func _poses() -> Array:
	var out: Array = []
	var root := _frontmatter()
	for id in root.tree.ids():
		var view := root.view_for(id)
		out.append([id, view.position, view.scale])
	return out
