extends GutTest

## #810 — StatBoard.stat_created (fired once, from the single mint site,
## _mint_stat) is what lets SkillNode subscribe to a sparse defender stat's
## value_changed at whatever moment it actually gets minted, and toggle a
## collision layer bit accordingly. Prerequisite for #811, which will query
## these bits via intersect_shape.
##
## Layer 1 (Godot's untouched default) stays set throughout — additive only,
## never disturbed — since intersect_point mouse picking
## (systems/player_input_controller.gd, ui/hud/minimap_panel/minimap_panel.gd,
## ui/frontmatter/menu_node_view.gd) depends on it.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")

var _node: SkillNode


func before_each() -> void:
	_node = _SKILL_NODE_SCENE.instantiate()


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _drag_bit() -> bool:
	return _node.get_collision_layer_value(SkillNode.DRAG_COLLISION_LAYER)


func _deflect_bit() -> bool:
	return _node.get_collision_layer_value(SkillNode.DEFLECT_COLLISION_LAYER)


func test_default_pickable_bit_survives_untouched() -> void:
	add_child(_node)
	await get_tree().physics_frame
	assert_true(_node.get_collision_layer_value(1),
			"the default pickable bit must stay on — the new bits are additive")
	assert_false(_drag_bit(), "a bare node carries neither defender stat")
	assert_false(_deflect_bit(), "a bare node carries neither defender stat")


func test_fortification_addon_attach_and_detach_toggles_drag_bit() -> void:
	add_child(_node)
	await get_tree().physics_frame
	assert_false(_drag_bit(), "precondition: no drag yet")

	var addon := _FORTIFICATION_SCENE.instantiate() as SkillNodeAddon
	_node.add_child(addon)
	await get_tree().physics_frame
	assert_true(_drag_bit(), "fortification's swing_drag mint flips the drag bit on")
	assert_false(_deflect_bit(), "fortification never touches deflection")

	_node.remove_child(addon)
	addon.free()
	await get_tree().physics_frame
	assert_false(_drag_bit(), "detaching fortification's modifier drops swing_drag back to 0 — bit off")


func test_bunker_addon_attach_and_detach_toggles_deflect_bit() -> void:
	add_child(_node)
	await get_tree().physics_frame
	assert_false(_deflect_bit(), "precondition: no deflection yet")

	var addon := _BUNKER_SCENE.instantiate() as SkillNodeAddon
	_node.add_child(addon)
	await get_tree().physics_frame
	assert_true(_deflect_bit(), "bunker's deflection mint flips the deflect bit on")
	assert_false(_drag_bit(), "bunker never touches swing_drag")

	_node.remove_child(addon)
	addon.free()
	await get_tree().physics_frame
	assert_false(_deflect_bit(), "detaching bunker's modifier drops deflection back to 0 — bit off")


## The #406 temporary-upgrade shape: a real addon attached to a node that is
## already ready, already in the tree, and has already been sitting there for
## several frames — not the "set the bit once at spawn" case a naive
## implementation gets right by accident. The subscription must be live no
## matter WHEN the mint happens, mirroring Entity.READY_GROUP's cautionary
## precedent (no writer hooked to the value changing = silent rot).
func test_addon_attached_well_after_the_node_is_already_established_still_flips_the_bit() -> void:
	add_child(_node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(_drag_bit(), "still nothing fortified several frames in")

	var addon := _FORTIFICATION_SCENE.instantiate() as SkillNodeAddon
	_node.add_child(addon)
	await get_tree().physics_frame
	assert_true(_drag_bit(), "a mid-lifetime attach mints swing_drag and the bit follows")


## Acceptance 3 — the registry is keyed on the LOCAL VALUE, never on addon
## identity: a bare granted StatModifier (no addon in sight) must flip the
## same bit an addon's local_modifiers would.
func test_bare_granted_modifier_without_an_addon_flips_the_drag_bit() -> void:
	add_child(_node)
	await get_tree().physics_frame
	assert_false(_drag_bit(), "precondition")

	var m := StatModifier.new()
	m.stat_id = &"swing_drag"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = 1.0
	_node.add_local_modifier(m)
	await get_tree().physics_frame
	assert_true(_drag_bit(), "a plain granted modifier mints swing_drag exactly like an addon would")

	_node.remove_local_modifier(m)
	await get_tree().physics_frame
	assert_false(_drag_bit(), "revoking the bare modifier drops the bit again")


## A node carrying both stats is one carrier of both kinds — both bits come
## on independently and neither addon's presence affects the other's bit.
func test_fortification_and_bunker_together_set_both_bits_independently() -> void:
	add_child(_node)
	await get_tree().physics_frame

	_node.add_child(_FORTIFICATION_SCENE.instantiate())
	await get_tree().physics_frame
	assert_true(_drag_bit())
	assert_false(_deflect_bit())

	_node.add_child(_BUNKER_SCENE.instantiate())
	await get_tree().physics_frame
	assert_true(_drag_bit(), "fortification's bit survives bunker's arrival")
	assert_true(_deflect_bit(), "bunker's bit is now on too")
