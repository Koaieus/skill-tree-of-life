extends GutTest

## [TerrainLedger]: per-world-turn samples of the booked terrain
## ([signal CombatWorld.terrain_booked]). The core assert, every case: per
## element, Δtotal = produced + effect − voided − decayed − onto_opposite
## − from_opposite against the previous sample (the first against the
## baseline).

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _fire: Element
var _light: Element
var _tm: TurnManager
var _ledger: TerrainLedger


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.reset_live()


func _c(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n) as NodeCombat


## A hub with [param k] leaves 3000 px out, owned by Red.
func _star(prefix: String, k: int) -> Array[SkillNode]:
	var x := _w.add_node(StringName(prefix + "X"), Vector2.ZERO)
	var out: Array[SkillNode] = [x]
	for i in k:
		var n := _w.add_node(StringName("%s%d" % [prefix, i]), Vector2.from_angle(TAU * i / k) * 3000.0)
		_w.link(x, n)
		out.append(n)
	_w.allocate(_red, out)
	await get_tree().process_frame
	return out


## A ledger bound to the live world, closed by its own TurnManager's signal.
func _open_ledger(window := 40) -> void:
	_tm = TurnManager.new()
	add_child_autofree(_tm)
	_ledger = TerrainLedger.new()
	_ledger.window_turns = window
	_ledger.turn_manager = _tm
	add_child_autofree(_ledger)


func _end_world_turn() -> void:
	CombatWorld.live().flow_temperature(1)
	_tm.world_turn_ended.emit()


func _hit(at: SkillNode) -> void:
	var d := DamageInstance.new()
	d.amount = 1.0
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.target = at
	d.attacker = _blue
	var span: Array[HitInstance] = [d]
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(span.duplicate()))
	OutcomeApplier.land_one(d, CombatWorld.live())


func _assert_invariant() -> void:
	var prev := _ledger.baseline()
	for s: Dictionary in _ledger.samples():
		for e: StringName in TerrainLedger.ELEMENTS:
			var r: Dictionary = s[e]
			var flows: int = r[&"produced"] + r[&"effect"] - r[&"voided"] - r[&"decayed"] \
					- r[&"onto_opposite"] - r[&"from_opposite"]
			assert_eq(int(r[&"total"]) - int(prev[e]), flows, "%s: Δtotal = the sample's flows" % e)
		prev = {}
		for e: StringName in TerrainLedger.ELEMENTS:
			prev[e] = s[e][&"total"]


func test_samples_close_on_world_turn_ended_and_the_ring_trims_to_the_window() -> void:
	_open_ledger(5)
	for _i in 7:
		_tm.world_turn_ended.emit()
	assert_eq(_ledger.samples().size(), 5, "trimmed to window_turns")
	_assert_invariant()


func test_decay_and_diffusion_are_counted_and_heat_onto_cold_is_its_own_line() -> void:
	var g := await _star("d", 2)
	_c(g[1]).add_terrain(_fire, 3 * _c(g[1]).terrain_threshold())
	_c(g[2]).add_terrain(_fire, -3 * _c(g[2]).terrain_threshold())
	_c(g[0]).add_terrain(_light, 2 * _c(g[0]).terrain_threshold())
	_open_ledger()
	_end_world_turn()
	_end_world_turn()
	var s: Dictionary = _ledger.samples()[0]
	assert_gt(int(s[&"heat"][&"decayed"]), 0, "Heat decays")
	assert_gt(int(s[&"cold"][&"decayed"]), 0, "Cold decays")
	assert_gt(int(s[&"charge"][&"decayed"]), 0, "Charge decays")
	_assert_invariant()


func test_heat_diffusing_onto_cold_counts_onto_opposite() -> void:
	var g := await _star("f", 1)
	_c(g[0]).add_terrain(_fire, 40)
	_c(g[1]).add_terrain(_fire, -1 - _c(g[1]).terrain_t())
	_open_ledger()
	var heat0 := _c(g[0]).terrain_t()
	CombatWorld.live().diffuse_temperature()
	_tm.world_turn_ended.emit()
	assert_lt(_c(g[0]).terrain_t(), heat0, "fixture: Heat flowed")
	var s: Dictionary = _ledger.samples()[0]
	assert_eq(int(s[&"heat"][&"onto_opposite"]), 1, "the 1 Cold it met")
	assert_eq(int(s[&"cold"][&"from_opposite"]), 1, "Cold's side mirrors it")
	_assert_invariant()


func test_a_live_landing_counts_and_a_shadow_resolve_adds_nothing() -> void:
	var g := await _star("s", 3)
	var x := g[0]
	_c(x).add_terrain(_light, _c(x).terrain_threshold() + 4 - _c(x).charge())
	_open_ledger()
	var shadow := CombatWorld.shadow()
	var d := DamageInstance.new()
	d.amount = 1.0
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.target = x
	d.attacker = _blue
	var span: Array[HitInstance] = [d]
	HitGather.stage_one(span.duplicate(), shadow, HitQueue.over(span.duplicate()))
	assert_false(d.terrain_sums.is_empty(), "fixture: the shadow gather booked sums")
	OutcomeApplier.land_one(d, shadow)
	shadow.free_shadow()
	assert_eq(int(_ledger.current()[&"charge"][&"effect"]), 0, "a shadow landing adds nothing")
	_hit(x)
	assert_eq(int(_ledger.current()[&"charge"][&"effect"]), 3, "the live landing counts")
	_end_world_turn()
	_assert_invariant()


func test_a_graph_snapshot_restore_clears_the_history() -> void:
	var g := await _star("r", 2)
	_c(g[0]).add_terrain(_fire, 5)
	_open_ledger()
	_end_world_turn()
	var bytes := GraphSnapshot.encode(_w.graph)
	_end_world_turn()
	assert_eq(_ledger.samples().size(), 2, "fixture: two samples")
	GraphSnapshot.decode(bytes, _w.graph)
	assert_true(_ledger.samples().is_empty(), "a restore clears the history")
	_end_world_turn()
	_assert_invariant()
