@tool
extends Control

## The LIVE frontmatter bench (#567 / #578) — the real `frontmatter_root.tscn`
## in a bloom [SubViewport], with a control column for every knob the motion
## notes flag as eyeballed.
##
## [b]It benches the shipped scene, not a mock.[/b] That is the #309 lesson,
## paid for once already: the tooltip fan's first live tab drove a hand-rolled
## copy of the fan's layout, no test covered the copy, and it drifted. The
## [SubViewport] below instances `frontmatter_root.tscn` itself, so what is
## tuned here is what ships — and when a knob has no visible effect, that is a
## finding about the menu rather than about the bench.
##
## [b]Why a bloom viewport.[/b] Glow is one [WorldEnvironment] pass PER VIEWPORT
## (`.claude/rules/hdr-color.md`), and `scenes/meta/meta_root.tscn`'s pass does
## not reach a [SubViewport] mounted here. `ui/theme/bloom_viewport.tscn` is the
## shared HDR-2D viewport the other live benches use; without it every
## [Emissive] tier in the menu would render flat and this tab would be judging
## the wrong picture.
##
## [b]The clock is driven, never watched.[/b] Every animated unit in this family
## exposes `set_progress(t)` and owns no [Tween]; the scrub slider writes `t`
## straight onto [method FrontmatterRoot.set_progress], which is the
## doc-blessed preview scrubber rather than a second drive model.
##
## [b]Knob state lives in one dictionary and is re-pushed wholesale.[/b]
## [method FrontmatterRoot.build] is idempotent by design — it clears what it
## made and rebuilds — so Rebuild is a real cold boot of the menu, and the only
## way the knobs survive it is for this panel to hold them and push them again.
## That also makes "does this knob do anything" answerable: the push is one
## function, [method _apply_all].
##
## Satisfies [SandboxLiveTab]'s loader contract with [method noop] — there is no
## inspected resource, same as `fan_live_panel.gd` and `node_visuals_panel.gd`.

const FRONTMATTER_SCENE_PATH := "res://ui/frontmatter/frontmatter_root.tscn"
const LAYOUT_SCRIPT_PATH := "res://ui/frontmatter/frontmatter_layout.gd"

## Knob ids. Strings only appear once, here, so a slider and its applier cannot
## drift apart.
const K_TRAVEL := &"travel_duration"
const K_REDUCE_MOTION := &"reduce_motion"
const K_NODE_RADIUS := &"node_radius"
const K_EDGE_ZOOM := &"edge_camera_zoom"
const K_EDGE_LIT_ALPHA := &"edge_lit_alpha"
const K_EDGE_UNLIT_ALPHA := &"edge_unlit_alpha"
const K_EDGE_GLOW := &"edge_lit_glow_stops"
const K_EDGE_DESATURATE := &"edge_unlit_desaturate"
const K_EDGE_DARKEN := &"edge_unlit_darken"
const K_PEEK_ALPHA := &"peek_preview_alpha"
const K_PEEK_HIDDEN := &"peek_hidden_alpha"
const K_BACK_REST := &"back_rest_stops"
const K_BACK_HOVER := &"back_hover_stops"
const K_BACK_SCALE := &"back_start_scale"
const K_TOOLTIP_SCALE := &"tooltip_start_scale"
## Geometry, in DESIGN PIXELS. The knobs are px because the motion notes and
## #567's table are px; [method _apply_geometry] converts to the ratios
## [FrontmatterLayout] actually stores, which is where they stay
## resolution-independent.
const K_HERO_X := &"hero_slot_x"
const K_HERO_Y := &"hero_slot_y"
const K_COLUMN_STEP := &"column_step"
const K_SIBLING_GAP := &"sibling_gap"
const K_PREVIEW_COLUMN := &"preview_column"
const K_PREVIEW_GAP := &"preview_gap"
const K_PREVIEW_SCALE := &"preview_scale"

## The geometry knobs as a set — what [method _reset_geometry] restores and what
## [method _apply_geometry] writes. One list, so a new ratio cannot be added to
## one of those and forgotten in the other.
const GEOMETRY_KEYS: Array[StringName] = [
	K_HERO_X, K_HERO_Y, K_COLUMN_STEP, K_SIBLING_GAP,
	K_PREVIEW_COLUMN, K_PREVIEW_GAP, K_PREVIEW_SCALE,
]

## Every knob's default, which is also the set of knobs [method _apply_all]
## knows how to push. Authored as the values the shipped scenes already carry,
## so opening the tab changes nothing until something is dragged.
const DEFAULTS := {
	K_TRAVEL: 0.85,
	K_REDUCE_MOTION: false,
	K_NODE_RADIUS: 32.0,
	K_EDGE_ZOOM: 1.0,
	K_EDGE_LIT_ALPHA: 1.0,
	K_EDGE_UNLIT_ALPHA: 0.55,
	K_EDGE_GLOW: 1.0,
	K_EDGE_DESATURATE: 0.6,
	K_EDGE_DARKEN: 0.35,
	K_PEEK_ALPHA: 0.45,
	K_PEEK_HIDDEN: 0.0,
	K_BACK_REST: 0.0,
	K_BACK_HOVER: 0.5,
	K_BACK_SCALE: 0.92,
	K_TOOLTIP_SCALE: 0.92,
	# The authored geometry, in design px — the same numbers
	# `FrontmatterLayout.reset_geometry()` restores. Literals rather than reads
	# of the live statics, because those are now mutable: a default computed
	# from them would silently become "whatever the last session left".
	# `test_the_geometry_defaults_are_the_authored_ratios` pins the agreement.
	K_HERO_X: 190.0,
	K_HERO_Y: 450.0,
	K_COLUMN_STEP: 306.0,
	K_SIBLING_GAP: 132.0,
	K_PREVIEW_COLUMN: 284.0,
	K_PREVIEW_GAP: 46.0,
	K_PREVIEW_SCALE: 0.42,
}

var _values: Dictionary = {}
var _hover_picker: OptionButton = null
## key -> the [HSlider] showing it, so a reset moves the handles rather than
## rebuilding the column out from under the button that asked for it.
var _sliders: Dictionary = {}
## Set while several knobs are being written at once, so one push happens at the
## end instead of one per knob.
var _batching: bool = false
var _geometry_readout: Label = null

@onready var _frontmatter: FrontmatterRoot = %Frontmatter
@onready var _knobs: VBoxContainer = %Knobs


func _ready() -> void:
	_values = DEFAULTS.duplicate()
	_build_controls()
	_apply_all()


## [SandboxLiveTab]'s `loader_method` target. This bench has no inspected
## resource to load — the menu tree is its own fixture.
func noop(_object: Object) -> void:
	pass


# --- the knobs ---------------------------------------------------------------

func _build_controls() -> void:
	_sliders = {}
	for child in _knobs.get_children():
		_knobs.remove_child(child)
		child.queue_free()

	_header("NAVIGATE")
	_navigation_grid()
	_button("‹  Back", "FrontmatterRoot.back() — the same call the edge affordance makes",
			func() -> void: _frontmatter.back())

	_header("HOVER")
	_hover_row()

	_header("MOTION")
	_slider(K_TRAVEL, "Travel", "travel_duration — seconds for the camera and the sprout together",
			0.0, 3.0, 0.01)
	_check(K_REDUCE_MOTION, "Reduce motion",
			"GameSettings.reduce_motion — every transition collapses to one frame")
	_scrub_row()

	_header("NODES + EDGES")
	_slider(K_NODE_RADIUS, "Node radius", "MenuNodeView.radius, in world units", 8.0, 64.0, 0.5)
	_slider(K_EDGE_ZOOM, "Edge zoom", "The edge shader's screen-constant width divisor "
			+ "(edge_camera_zoom) — drag it to see the #453 hairline behaviour", 0.25, 4.0, 0.05)
	_slider(K_EDGE_LIT_ALPHA, "Lit alpha", "MenuEdgeView.lit_alpha", 0.0, 1.0, 0.01)
	_slider(K_EDGE_UNLIT_ALPHA, "Unlit alpha", "MenuEdgeView.unlit_alpha", 0.0, 1.0, 0.01)
	_slider(K_EDGE_GLOW, "Lit glow (EV)", "MenuEdgeView.lit_glow_stops — Emissive tiers: "
			+ "0 INERT, 0.5 LABEL, 1 VALUE, 2 ALERT, 3 PEAK", 0.0, 4.0, 0.05)
	_slider(K_EDGE_DESATURATE, "Unlit desaturate", "MenuEdgeView.unlit_desaturate", 0.0, 1.0, 0.01)
	_slider(K_EDGE_DARKEN, "Unlit darken", "MenuEdgeView.unlit_darken", 0.0, 1.0, 0.01)

	_header("PEEK-AHEAD (#571)")
	_slider(K_PEEK_ALPHA, "Preview alpha", "HoverPreview.preview_alpha — how visible a "
			+ "peeked-at child is", 0.0, 1.0, 0.01)
	_slider(K_PEEK_HIDDEN, "Collapsed alpha", "HoverPreview.hidden_alpha — how visible a "
			+ "collapsed node is when nothing peeks at it", 0.0, 1.0, 0.01)

	_header("BACK AFFORDANCE (#572)")
	_slider(K_BACK_REST, "Rest tier (EV)", "BackAffordance.rest_stops", 0.0, 3.0, 0.05)
	_slider(K_BACK_HOVER, "Hover tier (EV)", "BackAffordance.hover_stops", 0.0, 3.0, 0.05)
	_slider(K_BACK_SCALE, "Start scale", "BackAffordance.start_scale", 0.5, 1.0, 0.01)

	_header("TOOLTIP (#575)")
	_slider(K_TOOLTIP_SCALE, "Start scale", "MenuTooltip.start_scale", 0.5, 1.0, 0.01)

	_header("GEOMETRY")
	_geometry_section()

	_header("EDITOR")
	_button("⟳  Rebuild", "FrontmatterRoot.build() from scratch, then re-push every knob",
			_rebuild)
	_button("✎  Open frontmatter_root.tscn", "Open the benched scene in the 2D editor",
			func() -> void: _open(FRONTMATTER_SCENE_PATH))
	_button("✎  Open frontmatter_layout.gd", "The solver these knobs write into — the geometry's single source of truth",
			func() -> void: _open(LAYOUT_SCRIPT_PATH))


## A button per menu id, so any depth is one click away rather than a traversal.
## Built in code because the row count is the TREE's, not this scene's — the
## same reason `sandbox_live_tab.gd` builds its breadcrumb in code.
func _navigation_grid() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	_knobs.add_child(grid)
	for id in _tree_ids():
		var button := Button.new()
		button.text = String(id)
		button.tooltip_text = "focus(&\"%s\")" % id
		button.pressed.connect(func() -> void: _frontmatter.focus(id))
		grid.add_child(button)


## Drives [method FrontmatterRoot.set_hovered], which is the one seam both the
## peek-ahead and the tooltip hang off. Nothing in the menu picks the mouse yet
## (#583), so this picker is the only hover source that exists.
func _hover_row() -> void:
	_hover_picker = OptionButton.new()
	_hover_picker.add_item("(none)")
	_hover_picker.set_item_metadata(0, &"")
	for id in _tree_ids():
		_hover_picker.add_item(String(id))
		_hover_picker.set_item_metadata(_hover_picker.item_count - 1, id)
	_hover_picker.tooltip_text = (
		"FrontmatterRoot.set_hovered() — drives the peek-ahead and the tooltip together. "
		+ "No mouse picking exists on menu nodes yet (#583), so this is the hover source."
	)
	_hover_picker.item_selected.connect(func(index: int) -> void:
		_frontmatter.set_hovered(_hover_picker.get_item_metadata(index) as StringName))
	_knobs.add_child(_hover_picker)


## The clock scrub: `t` written straight onto the running transition. Separate
## from [method _apply_all] because it is a moment, not a setting — re-pushing
## it after a rebuild would replay a frame nobody asked for.
func _scrub_row() -> void:
	var slider := _labelled_slider("Progress scrub", 0.0, 1.0, 0.005, 1.0,
			"Writes t straight onto FrontmatterRoot.set_progress — any frame of a transition")
	slider.value_changed.connect(func(v: float) -> void: _frontmatter.set_progress(v))


## The geometry #578 exists to stop eyeballing. Sliders in design px, applied
## onto [FrontmatterLayout]'s `static var` ratios and followed by a rebuild.
##
## [b]The solver stays the only implementation.[/b] The alternative — re-solving
## here with local overrides and writing positions onto the views — would have
## been a second layout, and #567 calls the solver the single source of truth.
## Writing its own inputs and asking it again is what keeps that true.
func _geometry_section() -> void:
	_slider(K_HERO_X, "Hero slot x", "Where the focused node sits, design px across 1440",
			0.0, 1440.0, 1.0, true)
	_slider(K_HERO_Y, "Hero slot y", "Where the focused node sits, design px down 900",
			0.0, 900.0, 1.0, true)
	_slider(K_COLUMN_STEP, "Column step",
			"Horizontal distance from a node to its children, design px", 60.0, 800.0, 1.0, true)
	_slider(K_SIBLING_GAP, "Sibling gap (min)",
			"Vertical pitch between siblings, design px — a FLOOR: _group_gap widens a "
			+ "group until adjacent subtrees clear each other by this much",
			40.0, 400.0, 1.0, true)
	_slider(K_PREVIEW_COLUMN, "Preview column",
			"Peek-ahead offset RIGHT OF THE HOVERED NODE, design px — relative, not "
			+ "an absolute x", 0.0, 800.0, 1.0, true)
	_slider(K_PREVIEW_GAP, "Preview gap", "Vertical pitch inside the collapsed stack, design px",
			10.0, 200.0, 1.0, true)
	_slider(K_PREVIEW_SCALE, "Preview scale", "Scale a collapsed / peeked-at node draws at",
			0.1, 1.0, 0.01, true)
	_button("⟲  Reset geometry",
			"FrontmatterLayout.reset_geometry() — the ratios are process-global now, "
			+ "so this is how a session ends without re-posing every menu built after it",
			_reset_geometry)
	_geometry_readout = Label.new()
	_geometry_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_geometry_readout.add_theme_font_size_override(&"font_size", 10)
	_knobs.add_child(_geometry_readout)
	_refresh_geometry_readout()


## The px knobs, converted to the fractions [FrontmatterLayout] stores. Ratios,
## never literals — that is what makes the layout resolution-independent, and
## the design viewport is the only place 1440x900 is allowed to appear.
func _apply_geometry() -> void:
	var design := FrontmatterLayout.DESIGN_VIEWPORT
	FrontmatterLayout.HERO_SLOT_RATIO = Vector2(
		float(_values[K_HERO_X]) / design.x, float(_values[K_HERO_Y]) / design.y
	)
	FrontmatterLayout.COLUMN_STEP_RATIO = float(_values[K_COLUMN_STEP]) / design.x
	FrontmatterLayout.SIBLING_GAP_RATIO = float(_values[K_SIBLING_GAP]) / design.y
	FrontmatterLayout.PREVIEW_COLUMN_RATIO = float(_values[K_PREVIEW_COLUMN]) / design.x
	FrontmatterLayout.PREVIEW_GAP_RATIO = float(_values[K_PREVIEW_GAP]) / design.y
	FrontmatterLayout.PREVIEW_SCALE = float(_values[K_PREVIEW_SCALE])


## Back to the authored ratios, and back to the sliders that show them. Also the
## teardown path — see [method _exit_tree].
func _reset_geometry() -> void:
	_batching = true
	for key: StringName in GEOMETRY_KEYS:
		_values[key] = DEFAULTS[key]
		var slider := _sliders.get(key) as HSlider
		if slider != null:
			slider.value = DEFAULTS[key]
	_batching = false
	FrontmatterLayout.reset_geometry()
	_rebuild()


## [b]The ratios are process-global mutable state now, so leaving them tuned
## would re-pose every menu built afterwards in the same process[/b] — another
## tab, a later test, the editor's own preview. Handing them back is this
## panel's responsibility because this panel is their sole writer.
##
## `_exit_tree` and not a visibility gate: the sandbox host hides an inactive tab
## rather than removing it, so this fires on a real teardown (reload, editor
## close, a test freeing the panel) and never mid-session.
func _exit_tree() -> void:
	FrontmatterLayout.reset_geometry()


func _refresh_geometry_readout() -> void:
	if _geometry_readout == null:
		return
	var design := FrontmatterLayout.DESIGN_VIEWPORT
	var hero := FrontmatterLayout.HERO_SLOT_RATIO
	_geometry_readout.text = "\n".join([
		"As stored (fractions of the %.0fx%.0f design viewport):" % [design.x, design.y],
		"  HERO_SLOT_RATIO      %.4f, %.4f" % [hero.x, hero.y],
		"  COLUMN_STEP_RATIO    %.4f" % FrontmatterLayout.COLUMN_STEP_RATIO,
		"  SIBLING_GAP_RATIO    %.4f" % FrontmatterLayout.SIBLING_GAP_RATIO,
		"  PREVIEW_COLUMN_RATIO %.4f" % FrontmatterLayout.PREVIEW_COLUMN_RATIO,
		"  PREVIEW_GAP_RATIO    %.4f" % FrontmatterLayout.PREVIEW_GAP_RATIO,
		"  PREVIEW_SCALE        %.4f" % FrontmatterLayout.PREVIEW_SCALE,
	])


# --- pushing the knobs -------------------------------------------------------

## Every knob, pushed onto the live menu in one pass. Called on ready, on any
## knob change, and after a rebuild — which is what makes a rebuild a real cold
## boot without losing the tuning.
func _apply_all() -> void:
	if _frontmatter == null or _frontmatter.tree == null:
		return
	_apply_geometry()
	_frontmatter.travel_duration = _values[K_TRAVEL]
	_frontmatter.reduce_motion = _values[K_REDUCE_MOTION]
	MenuEdgeView.push_camera_zoom(_values[K_EDGE_ZOOM])

	for id in _tree_ids():
		var view := _frontmatter.view_for(id)
		if view != null:
			view.radius = _values[K_NODE_RADIUS]
		var edge := _frontmatter.edge_for(id)
		if edge != null:
			edge.lit_alpha = _values[K_EDGE_LIT_ALPHA]
			edge.unlit_alpha = _values[K_EDGE_UNLIT_ALPHA]
			edge.lit_glow_stops = _values[K_EDGE_GLOW]
			edge.unlit_desaturate = _values[K_EDGE_DESATURATE]
			edge.unlit_darken = _values[K_EDGE_DARKEN]

	# [b]Unguarded, deliberately.[/b] All three widgets are part of the menu —
	# two authored in `frontmatter_root.tscn`, one minted by `build()` — so a
	# null here means the shell lost one, which is a bug to surface loudly
	# rather than a section to skip. A tolerant lookup is exactly what hid #572's
	# affordance being eaten by `_clear()` until this tab went looking.
	var peek := _hover_preview()
	peek.preview_alpha = _values[K_PEEK_ALPHA]
	peek.hidden_alpha = _values[K_PEEK_HIDDEN]
	# The bands only reach the views on the next apply, so re-state the current
	# hover rather than waiting for one.
	peek.apply(_frontmatter.focus_id, peek.hovered_id)

	var back := _back_affordance()
	back.rest_stops = _values[K_BACK_REST]
	back.hover_stops = _values[K_BACK_HOVER]
	back.start_scale = _values[K_BACK_SCALE]

	_tooltip().start_scale = _values[K_TOOLTIP_SCALE]

	_refresh_geometry_readout()


func _rebuild() -> void:
	_apply_geometry()
	_frontmatter.build()
	_apply_all()


# --- reaching into the benched scene -----------------------------------------

## `%` does not cross an instance boundary, but the instanced scene's ROOT owns
## its own unique names — so these go through [member _frontmatter] rather than
## through this panel. Documented because it is the exact trap
## `docs/domain/sandbox-framework.md` finding 3 records.
func _hover_preview() -> HoverPreview:
	return _frontmatter.get_node_or_null("%HoverPreview") as HoverPreview


func _back_affordance() -> BackAffordance:
	return _frontmatter.get_node_or_null("%BackAffordance") as BackAffordance


## The tooltip is minted in code by [FrontmatterRoot] (three levels of scene
## nesting break `%` resolution, so it cannot be authored in that scene), which
## means there is no node path to it — it is found by type under the panel layer.
func _tooltip() -> MenuTooltip:
	var layer := _frontmatter.get_node_or_null("%PanelLayer")
	if layer == null:
		return null
	for child in layer.get_children():
		if child is MenuTooltip:
			return child as MenuTooltip
	return null


func _tree_ids() -> Array[StringName]:
	var none: Array[StringName] = []
	if _frontmatter == null or _frontmatter.tree == null:
		return none
	return _frontmatter.tree.ids()


# --- control-column primitives -----------------------------------------------

func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.6, 0.85, 0.95, 0.85))
	label.add_theme_font_size_override(&"font_size", 10)
	_knobs.add_child(label)


## A knob-backed slider: writes [member _values] and re-pushes everything.
##
## [param rebuilds] is for the geometry knobs. Node positions are baked at build
## time and never recomputed — that IS #567's constraint 1 — so the only honest
## way to see a new ratio is a cold rebuild, which is exactly what
## [method FrontmatterRoot.build]'s documented idempotence is for.
func _slider(
	key: StringName, label: String, tooltip: String, min_v: float, max_v: float, step: float,
	rebuilds: bool = false
) -> void:
	var slider := _labelled_slider(label, min_v, max_v, step, _values[key], tooltip)
	_sliders[key] = slider
	slider.value_changed.connect(func(v: float) -> void:
		if _batching:
			return
		_values[key] = v
		if rebuilds:
			_rebuild()
		else:
			_apply_all())


func _labelled_slider(
	label: String, min_v: float, max_v: float, step: float, value: float, tooltip: String
) -> HSlider:
	var row := HBoxContainer.new()
	row.tooltip_text = tooltip
	_knobs.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(120.0, 0.0)
	name_label.add_theme_font_size_override(&"font_size", 11)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = tooltip
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "%.2f" % value
	value_label.custom_minimum_size = Vector2(44.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override(&"font_size", 11)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void: value_label.text = "%.2f" % v)
	return slider


func _check(key: StringName, label: String, tooltip: String) -> void:
	var check := CheckButton.new()
	check.text = label
	check.tooltip_text = tooltip
	check.button_pressed = _values[key]
	check.toggled.connect(func(on: bool) -> void:
		_values[key] = on
		_apply_all())
	_knobs.add_child(check)


func _button(label: String, tooltip: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	_knobs.add_child(button)


## Editor-only back-ref, same guard [method SandboxLiveTab._open_source] uses.
func _open(path: String) -> void:
	if not Engine.is_editor_hint():
		return
	if path.ends_with(".tscn"):
		EditorInterface.open_scene_from_path(path)
	else:
		EditorInterface.get_file_system_dock().navigate_to_path(path)
