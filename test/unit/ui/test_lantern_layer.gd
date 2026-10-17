extends GutTest

## [LanternLayer]: a view-only fog layer. A lantern of the local viewer's camp
## clears fog and gives the nodes under it their revealed look; nothing logical
## ([VisionSystem]'s visibility, picking, FogOverlay's circle set) moves.
##
## FogOverlay has no call counter, so "set_sources never runs" is proven through
## its only two triggers — `vision_render_tick` and `visibility_changed` — plus
## its material's `circle_count` staying put.

const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")
const _LANTERN_SCENE := preload("res://ui/fog_overlay/lantern.tscn")
const _CLAMP_ADDON_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")

## Far enough apart that the default vision range reaches only the owned node.
const _SPACING := 4000.0

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _enemy: Entity
## N0 owned (visible), N1 one hop out (sensed, carries an addon), N2 unlinked
## (fully hidden).
var _nodes: Array[SkillNode]
var _fog: FogOverlay
var _layer: LanternLayer


func before_each() -> void:
	var world := TestWorld.create(self)
	_graph = world.graph
	var at := {0: Vector2.ZERO, 1: Vector2(_SPACING, 0.0), 2: Vector2(0.0, _SPACING)}
	_nodes = world.build([[0, 1]], at)
	_nodes.append(world.add_node(&"N2", at[2]))
	_nodes[1].add_child(_CLAMP_ADDON_SCENE.instantiate())

	_alloc = world.allocator()
	_entity = world.add_entity("")
	_enemy = autofree(Entity.new())
	var camp := Faction.new()
	camp.id = &"lantern_enemy"
	_enemy.faction = camp
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _nodes[0])

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.viewers = [_entity]
	# Circles snap to target in one frame, so the vision loop is settled (and
	# silent) before any lantern moves.
	_vision.ease_rate = 0.0
	add_child_autofree(_vision)
	_fog = _FOG_SCENE.instantiate() as FogOverlay
	_fog.vision_system = _vision
	add_child_autofree(_fog)
	_layer = _fog.get_node(^"LanternLayer") as LanternLayer
	_vision._recompute()
	for i in 3:
		await get_tree().process_frame


func _lantern(source: Entity, pos: Vector2, parent: Node = self) -> Lantern:
	var l := _LANTERN_SCENE.instantiate() as Lantern
	l.source = source
	if parent == self:
		add_child_autofree(l)
	else:
		parent.add_child(l)
	l.global_position = pos
	return l


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_fixture_shape() -> void:
	assert_not_null(_layer, "fog_overlay.tscn instances a LanternLayer")
	assert_true(_vision.is_visible(_nodes[0]))
	assert_true(_vision.is_sensed(_nodes[1]), "N1 reads as sensed, one hop out")
	assert_false(_vision.is_visible(_nodes[2]) or _vision.is_sensed(_nodes[2]), "N2 is fully fogged")
	assert_eq(_layer.uploaded_count, 0, "no lanterns, nothing uploaded")


func test_own_camp_lantern_is_uploaded_enemy_is_not() -> void:
	var mine := _lantern(_entity, Vector2(100.0, 200.0))
	mine.radius = 90.0
	await _frames(2)
	assert_eq(_layer.uploaded_count, 1, "the viewer's lantern is uploaded")
	var px := _layer.image.get_pixel(0, 0)
	assert_almost_eq(px.r, mine.global_position.x, 0.01)
	assert_almost_eq(px.g, mine.global_position.y, 0.01)
	assert_almost_eq(px.b, mine.radius, 0.01)
	mine.free()
	await wait_until(func() -> bool: return _layer.uploaded_count == 0, _layer.fade_seconds + 0.2)
	_lantern(_enemy, Vector2(100.0, 200.0))
	await _frames(2)
	assert_eq(_layer.uploaded_count, 0, "an enemy-camp lantern is never uploaded")


func test_lantern_lights_a_fogged_node_and_leaving_clears_it() -> void:
	var n1 := _nodes[1]
	var addon: Node2D = n1.get_addons()[0]
	assert_false(addon.visible, "fixture: a sensed node hides its addons")
	var l := _lantern(_entity, n1.global_position)
	l.global_position += Vector2(l.radius * 0.5, 0.0)
	var n2 := _nodes[2]
	var l2 := _lantern(_entity, n2.global_position)
	await _frames(2)
	assert_true(n1.lantern_lit, "a sensed node inside the disc is lit")
	assert_true(addon.visible, "and shows its addons")
	assert_true(n2.lantern_lit, "a fully fogged node inside the disc is lit")
	assert_false(_nodes[0].lantern_lit, "a revealed node is never lantern-lit")
	l.global_position = n1.global_position + Vector2(l.radius * 3.0, 0.0)
	await _frames(2)
	assert_false(n1.lantern_lit, "moving the lantern away clears it")
	assert_false(addon.visible, "and the sensed look returns")
	assert_true(n2.lantern_lit, "the other lantern still holds its node")
	l2.free()
	await wait_until(func() -> bool: return not n2.lantern_lit, _layer.fade_seconds + 0.2)
	assert_false(n2.lantern_lit)


func test_moving_lanterns_touch_nothing_logical() -> void:
	var before := {}
	for n in _nodes:
		before[n] = [n.revealed, n.input_pickable, _vision.is_visible(n), _vision.is_sensed(n)]
	var circles_before = _fog.material.get_shader_parameter(&"circle_count")
	var sources_before := _vision.get_vision_sources().size()
	watch_signals(_vision)
	var a := _lantern(_entity, _nodes[1].global_position)
	var b := _lantern(_entity, _nodes[2].global_position)
	for i in 6:
		a.global_position += Vector2(-_SPACING / 6.0, 0.0)
		b.global_position += Vector2(_SPACING / 6.0, 0.0)
		await get_tree().process_frame
	for n in _nodes:
		assert_eq([n.revealed, n.input_pickable, _vision.is_visible(n), _vision.is_sensed(n)], before[n],
			"%s's logical state is untouched by lanterns" % n.name)
	assert_signal_not_emitted(_vision, "visibility_changed")
	assert_signal_not_emitted(_vision, "vision_render_tick", "so FogOverlay._refresh / set_sources never ran")
	assert_eq(_fog.material.get_shader_parameter(&"circle_count"), circles_before)
	assert_eq(_vision.get_vision_sources().size(), sources_before)


func test_freed_carrier_fades_out_then_the_layer_sleeps() -> void:
	var carrier := Node2D.new()
	add_child_autofree(carrier)
	var l := _lantern(_entity, _nodes[2].global_position, carrier)
	var r0 := l.radius
	await _frames(2)
	assert_true(_layer.is_processing())
	carrier.free()
	await get_tree().process_frame
	assert_eq(_layer.uploaded_count, 1, "the disc lingers as a fading ghost")
	var r := _layer.image.get_pixel(0, 0).b
	assert_lt(r, r0, "and is shrinking")
	await wait_until(func() -> bool: return _layer.uploaded_count == 0, _layer.fade_seconds + 0.2)
	assert_eq(_layer.uploaded_count, 0, "faded to nothing within fade_seconds")
	assert_false(_nodes[2].lantern_lit, "the last fade frame clears the lit set")
	assert_false(_layer.is_processing(), "and the layer sleeps")


func test_no_vision_system_lights_nothing() -> void:
	var bare := _FOG_SCENE.instantiate() as FogOverlay
	add_child_autofree(bare)
	_fog.queue_free()
	await get_tree().process_frame
	_lantern(_entity, _nodes[2].global_position)
	await _frames(2)
	assert_false(_nodes[2].lantern_lit, "with no fog system lantern_lit stays false")
