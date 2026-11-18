extends GutTest

## [method VisionSystem.sources_for]: the one answer to "which discs of sight
## do these viewers hold" — each owned node at its local `vision_range`, each
## scout row of a viewer's camp at [method ScoutStatus.radius_for], and nothing
## another camp holds.
##
## Layout: A (player camp) owns N0 (x=0) and N1 (x=50); B (npc camp) owns N2
## (x=300); C (camp_3) owns N5 (x=600), which A scouts. The fixture leaves
## `allocation_system` unset and calls `sources_for` directly.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SCOUTED: ScoutStatus = preload("res://effects/status/scouted.tres")
const _FACTIONS := [preload("res://entity/factions/player.tres"),
		preload("res://entity/factions/npc.tres"), preload("res://entity/factions/camp_3.tres")]

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _a: Entity
var _b: Entity
var _c: Entity
var _n0: SkillNode
var _n1: SkillNode
var _n2: SkillNode
var _n5: SkillNode


func before_each() -> void:
	_graph = TestWorld.create(self).graph
	_n0 = _spawn("N0", 0.0)
	_n1 = _spawn("N1", 50.0)
	_n2 = _spawn("N2", 300.0)
	_n5 = _spawn("N5", 600.0)

	_alloc = TestWorld.around(_graph).allocator()

	_a = _entity("A", 0)
	_b = _entity("B", 1)
	_c = _entity("C", 2)
	await get_tree().process_frame
	_alloc.force_allocate(_a, _n0)
	_alloc.force_allocate(_a, _n1)
	_alloc.force_allocate(_b, _n2)
	_alloc.force_allocate(_c, _n5)

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.viewers = [_a]
	add_child_autofree(_vision)
	await get_tree().process_frame


func _spawn(nm: String, x: float) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = Vector2(x, 0.0)
	_graph.skill_nodes_container.add_child(sn)
	return sn


func _entity(nm: String, faction: int) -> Entity:
	var en: Entity = autofree(Entity.new())
	en.display_name = nm
	en.faction = _FACTIONS[faction]
	en.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(en)
	return en


func _of_kind(sources: Array[VisionSource], kind: VisionSource.Kind) -> Array[VisionSource]:
	var out: Array[VisionSource] = []
	for s in sources:
		if s.kind == kind:
			out.append(s)
	return out


func _nodes(sources: Array[VisionSource]) -> Array:
	var out: Array = []
	for s in sources:
		out.append(s.node)
	return out


func test_owned_nodes_are_owned_sources_at_their_local_vision_range() -> void:
	var owned := _of_kind(_vision.sources_for([_a] as Array[Entity]), VisionSource.Kind.OWNED)
	assert_eq(owned.size(), 2, "A's two owned nodes, nothing else")
	assert_eq(_nodes(owned), [_n0, _n1], "A's nodes, never B's")
	for s in owned:
		assert_eq(s.kind, VisionSource.Kind.OWNED)
		assert_eq(s.center, s.node.global_position, "the disc sits on its node")
		assert_almost_eq(s.radius, float(s.node.get_local_value(&"vision_range")), 0.001,
				"radius is the node's local vision_range")


func test_a_scout_row_is_one_scout_source_for_the_firers_camp_only() -> void:
	_n5.get_combat().apply_status(_SCOUTED, 4.0, _a.faction.id, _a.entity_id)
	var a_sources := _vision.sources_for([_a] as Array[Entity])
	assert_eq(a_sources.size(), 3, "2 OWNED + 1 SCOUT")
	var scout := _of_kind(a_sources, VisionSource.Kind.SCOUT)
	assert_eq(scout.size(), 1, "one scout disc")
	if scout.size() == 1:
		assert_eq(scout[0].node, _n5, "on the scouted node")
		assert_eq(scout[0].center, _n5.global_position)
		assert_almost_eq(scout[0].radius, _SCOUTED.radius_for(_n5, 4), 0.001,
				"the def's radius for the row's stacks")
	var b_sources := _vision.sources_for([_b] as Array[Entity])
	assert_eq(_of_kind(b_sources, VisionSource.Kind.SCOUT).size(), 0, "B holds no scout disc of A's")
	assert_eq(_nodes(b_sources), [_n2], "B's call answers B's own node, none of A's")


func test_no_graph_no_sources() -> void:
	var bare: VisionSystem = autofree(VisionSystem.new())
	assert_eq(bare.sources_for([_a] as Array[Entity]).size(), 0)


# ── Burning nodes (BURNING): a light for every viewer ────────────────────────
# L (x=900, owned by nobody) hangs off M (x=1200) so its T is above 0.

var _disc_a := 0.0
var _disc_b := 0.0


func after_each() -> void:
	var disc := _disc()
	if disc != null and _disc_a > 0.0:
		disc.radius_a = _disc_a
		disc.radius_b = _disc_b
	CombatWorld.reset_live()


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _disc() -> DiscGoOff:
	return _fire().bands[0].go_off as DiscGoOff


func _lit_pair() -> SkillNode:
	var l := _spawn("L", 900.0)
	var m := _spawn("M", 1200.0)
	TestWorld.around(_graph).link(l, m)
	return l


## [param n]'s Heat set to its T + [param excess].
func _heat(n: SkillNode, excess: int) -> void:
	var c := n.get_combat()
	c.add_terrain(_fire(), c.terrain_threshold() + excess - c.terrain_t())


func _burning(viewers: Array[Entity]) -> Array[VisionSource]:
	return _of_kind(_vision.sources_for(viewers), VisionSource.Kind.BURNING)


func test_a_burning_node_is_a_burning_source_for_every_viewer() -> void:
	var l := _lit_pair()
	_heat(l, 2)
	assert_gt(l.get_combat().terrain_threshold(), 0, "sanity: T above 0")
	for v: Entity in [_a, _b, _c]:
		var lit := _burning([v] as Array[Entity])
		assert_eq(_nodes(lit), [l], "lit for %s, who owns nothing near it" % v.display_name)
	var src: VisionSource = _burning([_b] as Array[Entity])[0]
	assert_eq(src.center, l.global_position, "the disc sits on its node")


func test_the_light_is_the_discs_radius_at_two_powers() -> void:
	var l := _lit_pair()
	for p: int in [1, 4]:
		_heat(l, p)
		var lit := _burning([_a] as Array[Entity])
		assert_eq(lit.size(), 1)
		if lit.size() == 1:
			assert_almost_eq(lit[0].radius, _disc().disc_radius(p, l.radius), 0.001,
					"disc_radius(%d, R)" % p)


func test_a_lit_node_of_twice_the_radius_lights_twice_as_far() -> void:
	var l := _lit_pair()
	_heat(l, 3)
	var r1: float = _burning([_a] as Array[Entity])[0].radius
	l.base_radius *= 2.0
	var r2: float = _burning([_a] as Array[Entity])[0].radius
	assert_almost_eq(r2, 2.0 * r1, 0.001, "sized by the lit node's own radius")


func test_a_and_b_move_the_light_and_the_disc_together() -> void:
	var l := _lit_pair()
	var disc := _disc()
	_disc_a = disc.radius_a
	_disc_b = disc.radius_b
	var ratio := func() -> float:
		_heat(l, 1)
		var one: float = _burning([_a] as Array[Entity])[0].radius
		_heat(l, 4)
		return _burning([_a] as Array[Entity])[0].radius / one
	var before: float = ratio.call()
	disc.radius_b = _disc_b * 3.0
	var after: float = ratio.call()
	assert_ne(after, before, "a change to B moves the light")
	assert_almost_eq(after, disc.disc_radius(4, l.radius) / disc.disc_radius(1, l.radius), 0.0001,
			"…exactly as it moves the disc")


func test_the_light_is_gone_at_t() -> void:
	var l := _lit_pair()
	_heat(l, 1)
	assert_eq(_burning([_a] as Array[Entity]).size(), 1, "sanity: lit")
	_heat(l, 0)
	assert_eq(_burning([_a] as Array[Entity]).size(), 0, "at T: no light")


func test_a_heat_write_on_a_lit_node_refreshes_the_light() -> void:
	var l := _lit_pair()
	_vision._watch_statuses(l)
	_heat(l, 1)
	await get_tree().process_frame
	assert_false(_vision._recompute_deferred.is_queued(), "sanity: settled")
	_heat(l, 4)
	assert_true(_vision._recompute_deferred.is_queued(), "an excess move inside Burning requests one")
	await get_tree().process_frame
	var lit := _burning([_a] as Array[Entity])
	assert_eq(lit.size(), 1)
	if lit.size() == 1:
		assert_almost_eq(lit[0].radius, _disc().disc_radius(4, l.radius), 0.001)
	_heat(l, 0)
	assert_true(_vision._recompute_deferred.is_queued(), "dropping to T requests one")
	await get_tree().process_frame
	assert_eq(_burning([_a] as Array[Entity]).size(), 0, "its source is gone")


func test_an_unlit_write_and_a_shadow_write_request_nothing() -> void:
	var l := _lit_pair()
	_vision._watch_statuses(l)
	await get_tree().process_frame
	_heat(l, -1)
	assert_false(_vision._recompute_deferred.is_queued(), "unlit before and after: none")
	var shadow := CombatWorld.shadow()
	(shadow.combat_for(l) as NodeCombat).add_terrain(_fire(), 50)
	assert_false(_vision._recompute_deferred.is_queued(), "a shadow write: none")
	shadow.free_shadow()


func test_the_overflow_band_lights_by_the_whole_excess() -> void:
	var overflow: ElementBand = _fire().bands[1]
	assert_true(overflow.at_cap, "sanity: the overflow band")
	assert_true(overflow.light, "the overflow band lights")
	var l := _lit_pair()
	var c := l.get_combat()
	var tt := c.terrain_threshold()
	var cap := c.terrain_cap()
	c.add_terrain(_fire(), cap + 2 - c.terrain_t())
	assert_eq(c.terrain_band(_fire()), overflow, "sanity: past k × T")
	var lit := _burning([_a] as Array[Entity])
	assert_eq(lit.size(), 1)
	if lit.size() == 1:
		assert_almost_eq(lit[0].radius, _disc().disc_radius(cap + 2 - tt, l.radius), 0.001,
				"disc_radius(Heat − T, R), never Heat − k × T")
