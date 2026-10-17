extends GutTest
## The hero card is the inner ring's door: it carries an unspent-points badge
## bound to `ring_points`, and a click on the portrait opens the ring modal
## through [method HudRoot.open_ring].

const _GAME_ROOT := preload("res://test/support/route_probe_game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")

var _root: RouteProbeGameRoot
var _player: Entity


func before_each() -> void:
	_root = _GAME_ROOT.instantiate()
	_root.get_node("%TurnManager").opens_first_turn = false
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	await wait_physics_frames(2)
	var a := _SKILL_NODE.instantiate() as SkillNode
	a.name = "A"
	_root.graph.add_skill_node(a)
	var b := _SKILL_NODE.instantiate() as SkillNode
	b.name = "B"
	b.position = Vector2(120, 0)
	_root.graph.add_skill_node(b)
	_root.graph.add_edge(a, b)
	_player = _root.spawn_entity("P1", Color.CYAN, a, _BALANCED)
	_root.bind_player(_player)
	await wait_physics_frames(1)


func after_each() -> void:
	GameSession.end()


## Earn `k` ring points the way play does: by reaching milestone levels.
func _earn(k: int) -> void:
	var target := int(_player.level) + k * _player.milestone_level_interval
	target -= target % _player.milestone_level_interval
	while int(_player.level) < target:
		_player._on_xp_replenished()


func _card() -> HeroSigilCard:
	return _root.hud_root.hero_sigil_card


func _badge() -> Label:
	return _card().get_node("%RingBadge") as Label


## A real left click on the portrait (the sigil), pushed through the viewport.
func _click_portrait() -> void:
	var at := (_card().get_node("%SigilGlyph") as Control).get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		_card().get_viewport().push_input(ev, true)
	await wait_physics_frames(2)


func _drained() -> void:
	var applier := _root.command_applier
	while applier.is_applying:
		await applier.applying_changed
	await wait_physics_frames(1)


func test_no_points_no_badge() -> void:
	assert_false(_badge().visible, "a fresh hero has nothing to spend")


func test_minting_a_point_shows_the_badge_with_one() -> void:
	_earn(1)
	await wait_physics_frames(1)
	assert_true(_badge().visible, "an unspent point shows the badge")
	assert_eq(_badge().text, "1")


func test_clicking_the_card_opens_the_ring_modal() -> void:
	_earn(1)
	await _click_portrait()
	assert_true(_root.hud_root.ring_modal.visible, "a click on the portrait opens the ring")


func test_clicking_without_points_still_opens_the_ring() -> void:
	await _click_portrait()
	assert_true(_root.hud_root.ring_modal.visible, "the ring opens for review at zero")


func test_spending_to_zero_hides_the_badge() -> void:
	_earn(1)
	await wait_physics_frames(1)
	_root.command_applier.submit(SpendRingCellCommand.new(_player.entity_id, &"BleedingT1"))
	await _drained()
	assert_true(_player.ring_spent.has(&"BleedingT1"), "the buy applied")
	assert_false(_badge().visible, "no unspent points: no badge")


func test_unbinding_hides_the_badge() -> void:
	_earn(1)
	await wait_physics_frames(1)
	_card().bind(null)
	assert_false(_badge().visible, "a card bound to nobody shows no count")
