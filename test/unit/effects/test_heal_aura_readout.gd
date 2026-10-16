extends GutTest
## A heal aura grants no modifier, so its per-turn heal reaches the tooltip
## through the non-modifier payload row of [NodeEffectReadout.gather] — the
## row must equal what the real turn-start heal lands, hide where it lands 0,
## and a repeat hover must not re-walk distances.

var _w: TestWorld
var _entity: Entity
var _chain: Array[SkillNode] = []


func before_each() -> void:
	AuraDistanceCache.clear()
	_w = TestWorld.create(self)
	var board := TestBoards.flat_entity_board()
	# No level-up mid-turn (it would move node_health under the asserts).
	board.xp.base_value = 100000.0
	board.node_health.base_value = 100.0
	_entity = _w.add_entity("Healer", board)
	_entity.turns_taken = 1  # past the first-turn upkeep skip
	_chain = _w.build([[0, 1], [1, 2], [2, 3]])
	_w.allocate(_entity, _chain)
	await get_tree().process_frame


## base 10 over 3 hops, `v * (1 - d / max)`: 10, 6.667, 3.333, 0 — hop 1 is
## fractional on purpose, so the row must round the way the heal door does.
func _grant_aura() -> HealAuraEffect:
	var aura := HealAuraEffect.new()
	aura.display_name = "Sanctuary"
	aura.base = 10.0
	var reach := HopRangeFinder.new()
	reach.max_hops = 3
	aura.reach = reach
	var scale := ExpressionScale.new()
	scale.formula = "v * (1 - d / max)"
	aura.distance_scale = scale
	_entity.grant_effect(aura)
	return aura


func _heal_rows(node: SkillNode) -> Array[NodeEffectReadout]:
	var out: Array[NodeEffectReadout] = []
	for row in NodeEffectReadout.gather(node, _w.graph):
		if row.is_payload():
			out.append(row)
	return out


func _hp(node: SkillNode) -> float:
	return (node.node_board.get_stat(&"node_health") as PoolStat).current


func _true_damage(node: SkillNode, amount: float) -> void:
	var dmg := DamageInstance.new()
	dmg.amount = amount
	dmg.type = DamageInstance.Type.TRUE
	node.take_damage(amount, dmg)


func test_row_equals_the_real_turn_start_heal() -> void:
	var aura := _grant_aura()
	var hop1 := _chain[1]
	var rows := _heal_rows(hop1)
	assert_eq(rows.size(), 1, "one heal row on a node inside the aura")
	if rows.size() != 1:
		return
	assert_eq(rows[0].effect, aura, "row names the aura")
	assert_eq(rows[0].source_entity, _entity, "row carries its source entity")
	# Pre-damage so D-9's gated regen contributes 0 and the cap cannot clip.
	for n in _chain:
		_true_damage(n, 50.0)
	var before := _hp(hop1)
	_entity.begin_turn()
	var healed := _hp(hop1) - before
	assert_gt(healed, 0.0, "fixture sanity: the aura healed hop 1")
	assert_eq(rows[0].payload_amount, healed, "row value is the HP the turn start lands")


func test_no_row_where_the_heal_is_zero() -> void:
	_grant_aura()
	assert_eq(_heal_rows(_chain[3]).size(), 0, "the rim computes 0: no heal row")


func test_repeat_hover_walks_no_new_distances() -> void:
	_grant_aura()
	_heal_rows(_chain[1])
	assert_eq(AuraDistanceCache.walk_count, 1, "the first hover walks once, through the cache")
	var walks := AuraDistanceCache.walk_count
	_heal_rows(_chain[1])
	_heal_rows(_chain[2])
	assert_eq(AuraDistanceCache.walk_count, walks, "a warm hover re-walks nothing")


func test_panel_formats_the_heal_row() -> void:
	_grant_aura()
	var panel := preload("res://ui/tooltip_fan/panels/effect_readout_panel.tscn").instantiate() as EffectReadoutPanel
	add_child_autofree(panel)
	panel.bind(_chain[1], _w.graph)
	var texts: Array[String] = []
	for row in panel._rows.get_children():
		texts.append((row as SlabRow)._label.text)
	assert_has(texts, "Sanctuary: +7 HP/turn", "hop 1's 6.667 lands as 7 whole HP")
