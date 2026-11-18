extends GutTest

## [StatusOverlay]'s Catalyst layer on a skill node: one crystal per stack
## (clamped at `crystal_cap`), drawn by its own overlay outside the health
## bar's fade, and a conversion pulse heard on the node's own
## [signal SkillNode.catalyst_converted], tinted by [method StatusOverlay.pulse_tint].
## Reads the model (`crystals` / `pulse_crystals` / `is_pulsing`), never pixels.

const _CATALYST: CatalystStatus = preload("res://effects/status/catalyst.tres")

const _HP := 100.0

var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	var world := TestWorld.create(self)
	_alloc = world.allocator()
	_entity = world.add_entity("", TestBoards.flat_entity_board())
	_nodes = world.build([[0, 1], [0, 2]])
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _nodes[1])
	_entity.core_location = _nodes[1]
	_alloc.force_allocate(_entity, _nodes[0])
	_entity.stat_board.get_stat(&"node_health").base_value = _HP
	_nodes[0].get_max_hp()
	(_nodes[0].node_board.get_stat(&"node_health") as PoolStat).set_current(_HP)
	await get_tree().process_frame


func _layer(node: SkillNode) -> StatusOverlay:
	return node.get_node_or_null(^"Visuals/CatalystLayer") as StatusOverlay


func _element(id: StringName) -> Element:
	return ElementRoster.shared().by_id(id)


func _has_faded_ancestor(n: Node, stop: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != stop:
		if p is HealthBar:
			return true
		p = p.get_parent()
	return false


# ── Crystals ────────────────────────────────────────────────────────────────

func test_a_full_hp_carrier_shows_crystals_outside_the_bar_fade() -> void:
	_nodes[0].get_combat().apply_status(_CATALYST, 3.0)
	var layer := _layer(_nodes[0])
	assert_not_null(layer, "the node has its own Catalyst layer")
	if layer == null:
		return
	assert_eq(layer.crystals.size(), 3, "one crystal per stack")
	assert_false(_has_faded_ancestor(layer, _nodes[0]), "no health bar fades the crystals")
	var bar := _nodes[0].get_node("Visuals/HealthBar") as HealthBar
	assert_almost_eq(bar.modulate.a, 0.0, 0.001, "fixture: the full-HP bar is faded out")
	var bar_overlay := bar.get_node("StatusOverlay") as StatusOverlay
	assert_eq(bar_overlay.crystals.size(), 0, "the bar's overlay draws no crystals")


func test_crystals_clamp_at_the_cap() -> void:
	var layer := _layer(_nodes[0])
	assert_not_null(layer)
	if layer == null:
		return
	_nodes[0].get_combat().apply_status(_CATALYST, float(layer.crystal_cap + 3))
	assert_eq(layer.crystals.size(), layer.crystal_cap, "more stacks than the cap show as the cap")


# ── Pulse tint ──────────────────────────────────────────────────────────────

func test_the_pulse_takes_the_element_that_made_the_most_stacks() -> void:
	var fire := _element(&"fire")
	var ice := _element(&"ice")
	var tint := StatusOverlay.pulse_tint({fire.id(): 1, ice.id(): 3}, Color.BLACK)
	assert_eq(tint, ice.identity.tint)


func test_a_tie_takes_the_first_element_named() -> void:
	var fire := _element(&"fire")
	var ice := _element(&"ice")
	assert_eq(StatusOverlay.pulse_tint({ice.id(): 2, fire.id(): 2}, Color.BLACK), ice.identity.tint)
	assert_eq(StatusOverlay.pulse_tint({fire.id(): 2, ice.id(): 2}, Color.BLACK), fire.identity.tint)


func test_a_conversion_naming_no_element_keeps_the_fallback() -> void:
	assert_eq(StatusOverlay.pulse_tint({}, Color.BLACK), Color.BLACK)
	assert_eq(StatusOverlay.pulse_tint({&"no_such_element": 4}, Color.BLACK), Color.BLACK)


# ── The node-local cue ──────────────────────────────────────────────────────

func test_the_pulse_hears_only_its_own_node() -> void:
	var layer := _layer(_nodes[0])
	assert_not_null(layer)
	if layer == null:
		return
	_nodes[2].catalyst_converted.emit({})
	assert_false(layer.is_pulsing(), "another node's conversion is not this one's")
	_nodes[0].catalyst_converted.emit({})
	assert_true(layer.is_pulsing(), "its own node's conversion pulses")


func test_a_fully_spent_row_still_pulses_the_crystals_it_had() -> void:
	var combat := _nodes[0].get_combat()
	combat.apply_status(_CATALYST, 3.0)
	var layer := _layer(_nodes[0])
	assert_not_null(layer)
	if layer == null:
		return
	combat.adjust_status_power(_CATALYST, -3.0)
	assert_eq(layer.crystals.size(), 0, "fixture: the take spent the row")
	_nodes[0].catalyst_converted.emit({_element(&"fire").id(): 3})
	assert_eq(layer.pulse_crystals.size(), 3, "the pulse flashes the crystals spent")


# ── Fog ─────────────────────────────────────────────────────────────────────

func test_a_fogged_carrier_hides_its_crystals_and_pulse() -> void:
	_nodes[0].get_combat().apply_status(_CATALYST, 3.0)
	var layer := _layer(_nodes[0])
	assert_true(layer.visible, "fixture: a revealed carrier shows its crystals")
	_nodes[0].revealed = false
	assert_false(layer.visible, "fog hides a carrier's Catalyst")
	_nodes[0].catalyst_converted.emit({})
	assert_false(layer.visible, "nor does a fogged conversion pulse")
	_nodes[0].lantern_lit = true
	assert_true(layer.visible, "a lantern gives the revealed look")
	_nodes[0].lantern_lit = false
	_nodes[0].revealed = true
	assert_true(layer.visible, "revealed again, the crystals return")
