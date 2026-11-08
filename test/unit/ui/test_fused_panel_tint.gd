extends GutTest

## #1771 (child 1 of #435): FusedPanel's `border_color`, `border_width` and
## `glow_color` are per-panel `instance uniform`s, defaulting to the values the
## shared material used to bake — so a tinted site varies them without a
## per-node material, and batching survives.

const _DEFAULT_GLOW_COLOR := Color(0.4, 0.95, 1.0, 1.0)
const _DEFAULT_BORDER_COLOR := Color(0.47, 0.55, 0.75, 0.16)
const _DEFAULT_BORDER_WIDTH := 1.0

const _TINT_GLOW := Color(1.0, 0.6, 0.2, 1.0)
const _TINT_BORDER := Color(0.9, 0.3, 0.3, 0.5)
const _TINT_WIDTH := 2.5


func _add(panel: FusedPanel) -> FusedPanel:
	add_child(panel)
	autofree(panel)
	return panel


func _param(panel: FusedPanel, name: StringName) -> Variant:
	return panel.get_instance_shader_parameter(name)


func test_fresh_panel_reports_todays_shared_values() -> void:
	var panel := _add(FusedPanel.new())
	assert_eq(_param(panel, &"glow_color"), _DEFAULT_GLOW_COLOR, "glow_color defaults to the old baked value")
	assert_eq(_param(panel, &"border_color"), _DEFAULT_BORDER_COLOR, "border_color defaults to the old baked value")
	assert_eq(_param(panel, &"border_width"), _DEFAULT_BORDER_WIDTH, "border_width defaults to the old baked value")


func test_values_set_before_entering_the_tree_land_on_ready() -> void:
	var panel := FusedPanel.new()
	panel.glow_color = _TINT_GLOW
	panel.border_color = _TINT_BORDER
	panel.border_width = _TINT_WIDTH
	_add(panel)
	assert_eq(_param(panel, &"glow_color"), _TINT_GLOW)
	assert_eq(_param(panel, &"border_color"), _TINT_BORDER)
	assert_eq(_param(panel, &"border_width"), _TINT_WIDTH)


func test_values_set_in_the_tree_push_live() -> void:
	var panel := _add(FusedPanel.new())
	panel.glow_color = _TINT_GLOW
	panel.border_color = _TINT_BORDER
	panel.border_width = _TINT_WIDTH
	assert_eq(_param(panel, &"glow_color"), _TINT_GLOW)
	assert_eq(_param(panel, &"border_color"), _TINT_BORDER)
	assert_eq(_param(panel, &"border_width"), _TINT_WIDTH)


## "Batching holds": no per-node material is ever authored — an untouched panel
## carries no material of its own before `_ready`, and a tinted panel shares
## the very same material object as an untouched one once both are in the tree.
func test_tinting_keeps_the_one_shared_material() -> void:
	var plain := FusedPanel.new()
	assert_null(plain.material, "an untouched panel authors no material of its own")
	var tinted := FusedPanel.new()
	tinted.glow_color = _TINT_GLOW
	tinted.border_color = _TINT_BORDER
	tinted.border_width = _TINT_WIDTH
	_add(plain)
	_add(tinted)
	var shared := FusedPanel._shared_material()
	assert_same(plain.material, shared, "untouched panel rides the shared material")
	assert_same(tinted.material, shared, "tinted panel still rides the same shared material")
