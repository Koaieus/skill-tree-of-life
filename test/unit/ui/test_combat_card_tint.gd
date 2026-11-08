extends GutTest

## #1773 (child 3 of #435): a combat card's panel is a [FusedPanel] riding the
## shared material, and the selected-mode tint lands on its per-panel instance
## uniforms — `border_color` takes the card's `mode_color` (already lifted via
## [method Emissive.at]) and `glow` lights; deselecting puts both back to the
## untinted FusedPanel defaults.

const _MAGIC := preload("res://ui/hud/combat_readout/combat_card_magic.tscn")
const _MELEE := preload("res://ui/hud/combat_readout/combat_card_melee.tscn")

const _DEFAULT_BORDER_COLOR := Color(0.47, 0.55, 0.75, 0.16)
const _DEFAULT_BORDER_WIDTH := 1.0


func _panel_of(card: Node) -> FusedPanel:
	var found := card.find_children("*", "FusedPanel", true, false)
	assert_eq(found.size(), 1, "the card carries exactly one FusedPanel")
	if found.size() != 1:
		return null
	return found[0] as FusedPanel


func _param(panel: FusedPanel, name: StringName) -> Variant:
	return panel.get_instance_shader_parameter(name)


func test_active_card_tints_its_fused_panel_and_inactive_resets() -> void:
	for scene: PackedScene in [_MAGIC, _MELEE]:
		var card := scene.instantiate() as CombatReadoutCard
		add_child_autofree(card)
		var panel := _panel_of(card)
		if panel == null:
			return
		card.set_active(true)
		assert_eq(_param(panel, &"border_color"), card.mode_color,
			"%s: active border is the mode colour" % card.name)
		assert_gt(_param(panel, &"border_width") as float, _DEFAULT_BORDER_WIDTH,
			"%s: active border is thicker than the hairline" % card.name)
		assert_gt(_param(panel, &"glow") as float, 0.0, "%s: active glow is lit" % card.name)
		card.set_active(false)
		assert_eq(_param(panel, &"border_color"), _DEFAULT_BORDER_COLOR,
			"%s: inactive border is the FusedPanel default" % card.name)
		assert_eq(_param(panel, &"border_width"), _DEFAULT_BORDER_WIDTH,
			"%s: inactive border width is the default" % card.name)
		assert_eq(_param(panel, &"glow"), 0.0, "%s: inactive glow is off" % card.name)


## Batching holds: no card authors its own material — the panel uses the one
## shared FusedPanel material.
func test_card_panel_shares_the_fused_material() -> void:
	var card := _MAGIC.instantiate()
	add_child_autofree(card)
	var panel := _panel_of(card)
	if panel == null:
		return
	assert_same(panel.material, FusedPanel._shared_material(), "the card panel rides the shared material")
