extends GutTest
## Pinning an entity's core in the node inspector reads its build: the ring
## silhouette (sector hues + depth), shown only while the local player can
## see that core. A non-core node, or a fogged core, shows no wheel.

const _GAME_ROOT := preload("res://test/support/route_probe_game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")

var _root: RouteProbeGameRoot
var _player: Entity
var _near: Entity
var _far: Entity
var _plain: SkillNode


func before_each() -> void:
	_root = _GAME_ROOT.instantiate()
	_root.get_node("%TurnManager").opens_first_turn = false
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	await wait_physics_frames(2)
	var a := _add_node("A", Vector2.ZERO)
	var b := _add_node("B", Vector2(120, 0))
	var c := _add_node("C", Vector2(240, 0))
	_plain = _add_node("Plain", Vector2(-120, 0))
	_root.graph.add_edge(a, b)
	_root.graph.add_edge(b, c)
	_root.graph.add_edge(a, _plain)
	var far := _add_node("Far", Vector2(6000, 0))
	_player = _root.spawn_entity("P1", Color.CYAN, a, _BALANCED)
	_near = _root.spawn_entity("Near", Color.RED, c, _BALANCED)
	_far = _root.spawn_entity("Far", Color.ORANGE, far, _BALANCED)
	_root.bind_player(_player)
	# The fixture's entities carry no faction, so no seat sets the viewers:
	# the local player is the one who sees, as a level's seat makes it.
	_root.vision_system.viewers = [_player] as Array[Entity]
	await wait_physics_frames(2)


func after_each() -> void:
	GameSession.end()


func _add_node(n: String, at: Vector2) -> SkillNode:
	var node := _SKILL_NODE.instantiate() as SkillNode
	node.name = n
	node.position = at
	_root.graph.add_skill_node(node)
	return node


## Earn one ring point the way play does (a milestone level), then buy `cell`.
func _buy(e: Entity, cell: StringName) -> void:
	var target := int(e.level) + e.milestone_level_interval
	target -= target % e.milestone_level_interval
	while int(e.level) < target:
		e._on_xp_replenished()
	_root.command_applier.submit(SpendRingCellCommand.new(e.entity_id, cell))
	var applier := _root.command_applier
	while applier.is_applying:
		await applier.applying_changed
	await wait_physics_frames(1)
	assert_true(e.ring_spent.has(cell), "arrange: the buy applied")


func _pin(node: SkillNode) -> void:
	_root.input_ctl.node_pinned.emit(node)
	await wait_physics_frames(1)


func _wheel() -> AspectWheel:
	return _root.hud_root.node_inspector_card.get_node("%RingWheel") as AspectWheel


## Wedges drawn past the unbought floor — the aspects the build has bought.
func _bought_wedges() -> int:
	var w := _wheel()
	var floor_r := w.inner_radius_px + (w.radius_px - w.inner_radius_px) * w.min_fill
	var n := 0
	for i in w.entry_count():
		if w.fill_radius(i) > floor_r + 0.01:
			n += 1
	return n


func test_pinning_a_visible_enemy_core_shows_its_bought_aspects() -> void:
	await _buy(_near, &"BleedingT1")
	assert_true(_root.vision_system.is_visible(_near.core_location), "arrange: the enemy core is in view")
	await _pin(_near.core_location)
	assert_true(_wheel().visible, "a visible enemy core shows its silhouette")
	assert_eq(_bought_wedges(), 1, "the one bought aspect reads on the wheel")


func test_pinning_a_non_core_node_shows_no_wheel() -> void:
	await _pin(_plain)
	assert_false(_wheel().visible, "a non-core node has no build to show")


func test_pinning_a_fogged_core_shows_no_wheel() -> void:
	await _buy(_far, &"BleedingT1")
	assert_false(_root.vision_system.is_visible(_far.core_location), "arrange: the far core is fogged")
	await _pin(_far.core_location)
	assert_false(_wheel().visible, "a core you cannot see shows nothing")


func test_pinning_the_own_core_shows_its_wheel() -> void:
	await _buy(_player, &"BleedingT1")
	await _pin(_player.core_location)
	assert_true(_wheel().visible, "your own core shows your build")
	assert_eq(_bought_wedges(), 1, "the own bought aspect reads too")


func test_repinning_away_from_a_core_hides_the_wheel() -> void:
	await _pin(_player.core_location)
	await _pin(_plain)
	assert_false(_wheel().visible, "leaving the core drops the wheel")
