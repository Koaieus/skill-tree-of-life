extends GutTest

## #1801 C — the Catalyst core, additive. [CatalystStatus]'s pure split
## [method CatalystStatus.converted], its ratio and its k × T cap; the
## row-taking [method CatalystStatus.convert] the land step and the settle seat
## share; and the prime conversion seated in the settle routine
## ([TerrainSettle.PrimeConversion]). Acceptance 1 (through `converted()` and
## `convert()` alone), 2 (the settle routine called directly) and 4's cap.
## The probe def is built here; the shipped-def cases at the end read `catalyst.tres` (acceptance 1's centre, 3, 4, 4b). Fixture: A - B - C, B owned (graph degree 2); T and the cap
## are read off B, never a literal.

var _w: TestWorld
var _node: NodeCombat
var _b: SkillNode
var _holder: Entity
var _attacker: Entity
var _def: CatalystStatus
var _fire: Element
var _ice: Element
var _lightning: Element
var _heat_id: StringName
var _cold_id: StringName
var _charge_id: StringName


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	var holder := _w.add_entity("P")
	_holder = holder
	_attacker = _w.add_entity("Q")
	var a := _w.add_node(&"A")
	var b := _w.add_node(&"B")
	var c := _w.add_node(&"C")
	_w.link(a, b)
	_w.link(b, c)
	b.owned_by = holder
	holder.navigator.mirror_add(b)
	await get_tree().process_frame
	_node = b.get_combat()
	_b = b
	var roster := ElementRoster.shared()
	_fire = roster.by_id(&"fire")
	_ice = roster.by_id(&"ice")
	_lightning = roster.by_id(&"lightning")
	_heat_id = _fire.id()
	_cold_id = _ice.id()
	_charge_id = _lightning.id()
	_def = CatalystStatus.new()
	_def.id = &"catalyst_probe"
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	_def.power_max = 0.0
	_def.decay = FlatDecay.new()


func after_each() -> void:
	StatusRoster.shared().statuses.erase(_def)
	CombatWorld.reset_live()


func _t() -> int:
	return _node.terrain_threshold()


func _store() -> int:
	return int(_node.get_status_power(_def.id))


func _plant(n: int) -> void:
	_node.apply_status(_def, float(n))


func _put(t: int, charge: int) -> void:
	_node.add_terrain(_fire, t - _node.terrain_t())
	_node.add_terrain(_lightning, charge - _node.charge())


## One settle commit of [param net_t] / [param charge] on B with the prime
## conversion seated over the test's def.
func _settle(net_t: int, charge: int = 0) -> void:
	var batch := TerrainSettle.Batch.new()
	if net_t != 0:
		batch.add_net_t(_node, net_t)
	if charge != 0:
		batch.add_charge(_node, charge)
	var readers: Array[TerrainSettle.SettleReader] = [TerrainSettle.PrimeConversion.new(_def)]
	TerrainSettle.commit_with(batch, readers)


func _sum(d: Dictionary) -> int:
	var total := 0
	for k: Variant in d:
		total += int(d[k])
	return total


# ── Acceptance 1 through converted() / convert() alone ───────────────────────


func test_three_catalyst_and_a_two_heat_hit_give_five_heat_and_the_row_ends_at_zero() -> void:
	assert_eq(CatalystStatus.converted(3, {_heat_id: 2}), {_heat_id: 3}, "the whole store goes to the one landing element")
	_plant(3)
	var out := _def.convert(_node, {_heat_id: 2})
	assert_eq(2 + int(out.get(_heat_id, 0)), 5, "the hit's 2 Heat plus the 3 converted")
	assert_eq(_store(), 0, "the row ends at 0")


func test_cold_and_charge_convert_the_same_way() -> void:
	for id: StringName in [_cold_id, _charge_id]:
		assert_eq(CatalystStatus.converted(3, {id: 2}), {id: 3}, "%s: the whole store converts" % id)
		_plant(3)
		var out := _def.convert(_node, {id: 2})
		assert_eq(2 + int(out.get(id, 0)), 5, "%s: 2 landing plus 3 converted" % id)
		assert_eq(_store(), 0, "%s: the row ends at 0" % id)


func test_a_landing_with_no_terrain_stack_leaves_catalyst_alone() -> void:
	assert_eq(CatalystStatus.converted(3, {}), {}, "nothing lands, nothing converts")
	_plant(3)
	assert_eq(_def.convert(_node, {}), {}, "convert() returns nothing")
	assert_eq(_store(), 3, "the row is untouched")


func test_the_primary_element_plays_no_part() -> void:
	var script: Script = load("res://effects/status/catalyst.gd")
	var found := false
	for m: Dictionary in script.get_script_method_list():
		if m.name == &"converted":
			found = true
			assert_eq((m.args as Array).size(), 2, "converted(store, landing): no primary element")
	assert_true(found, "converted() is on the script")
	assert_eq(CatalystStatus.converted(3, {_charge_id: 1}), {_charge_id: 3},
			"a lone Charge stack converts the store to Charge, whatever carries it")
	_plant(3)
	assert_eq(_def.convert(_node, {_charge_id: 1}), {_charge_id: 3}, "convert(): the row goes to Charge")


func test_the_split_one_to_two_with_no_remainder() -> void:
	var landing := {_heat_id: 1, _charge_id: 2}
	assert_eq(CatalystStatus.converted(3, landing), {_heat_id: 1, _charge_id: 2}, "3 over 1 + 2 is 1 : 2")
	_plant(3)
	var out := _def.convert(_node, landing)
	assert_eq(1 + int(out.get(_heat_id, 0)), 2, "the node gains 2 Heat")
	assert_eq(2 + int(out.get(_charge_id, 0)), 4, "the node gains 4 Charge")
	assert_eq(_store(), 0, "the row ends at 0")


func test_the_split_hands_the_leftover_to_the_largest_remainder() -> void:
	assert_eq(CatalystStatus.converted(5, {_heat_id: 1, _charge_id: 2}), {_heat_id: 2, _charge_id: 3},
			"shares 1.67 / 3.33: floors 1 / 3, the one leftover to Heat's .67")


func test_a_tied_leftover_stays_catalyst() -> void:
	var landing := {_heat_id: 1, _charge_id: 1}
	assert_eq(CatalystStatus.converted(3, landing), {_heat_id: 1, _charge_id: 1}, "3 over 1 + 1: one each")
	_plant(3)
	_def.convert(_node, landing)
	assert_eq(_store(), 1, "the tied leftover stays Catalyst")
	_node.remove_status(_def.id)
	assert_eq(CatalystStatus.converted(1, landing), {}, "1 over 1 + 1 converts nothing")
	_plant(1)
	assert_eq(_def.convert(_node, landing), {}, "the node gains only the hit's own stacks")
	assert_eq(_store(), 1, "1 Catalyst stays")


func test_three_elements_carry_the_same_rule_over() -> void:
	# Tentative (not the owner's): a tied group the leftover covers gets one each;
	# one it cannot cover stays Catalyst.
	assert_eq(CatalystStatus.converted(7, {&"a": 2, &"b": 2, &"c": 1}), {&"a": 3, &"b": 3, &"c": 1},
			"leftover 2 covers the tied pair")
	assert_eq(CatalystStatus.converted(4, {&"a": 1, &"b": 1, &"c": 1}), {&"a": 1, &"b": 1, &"c": 1},
			"leftover 1 cannot pick among three: it stays")


func test_every_split_conserves_the_store() -> void:
	var cases := [
		[3, {_heat_id: 2}], [3, {_heat_id: 1, _charge_id: 2}], [5, {_heat_id: 1, _charge_id: 2}],
		[3, {_heat_id: 1, _charge_id: 1}], [1, {_heat_id: 1, _charge_id: 1}], [3, {}],
		[11, {_heat_id: 3, _cold_id: 1, _charge_id: 5}],
	]
	for c: Array in cases:
		var parts := CatalystStatus.converted(c[0], c[1])
		for k: Variant in parts:
			assert_gt(int(parts[k]), 0, "%s: no empty part" % [c])
		assert_true(_sum(parts) <= c[0], "%s: no stack minted" % [c])
		_node.remove_status(_def.id)
		_plant(c[0])
		var out := _def.convert(_node, c[1])
		assert_eq(_sum(out) + _store(), c[0], "%s: converted plus leftover equal the store" % [c])


func test_the_ratio_scales_the_result() -> void:
	_def.ratio_out = 2
	_plant(3)
	var out := _def.convert(_node, {_heat_id: 2})
	assert_eq(2 + int(out.get(_heat_id, 0)), 2 + 3 * _def.ratio_out / float(_def.ratio_in), "3 Catalyst at 1 : 2 is 6 Heat, 8 with the hit's 2")
	assert_eq(_store(), 0, "the whole store traded")


# ── Acceptance 1 through #1798's land step ───────────────────────────────────
# HitGather.stage_one on the live world: the land step converts the node's
# Catalyst over everything landing there, through CatalystStatus.convert, and
# the converted stacks join that node's terrain write. The record of the take
# (row_ops, a rebuilt or re-drained beat) is test/unit/attack/
# test_catalyst_land_record.gd's.

## A head by Q on [param n]: TRUE damage and one raw terrain rider per
## [param riders] entry (Element → stacks).
func _hit_on(n: SkillNode, riders: Dictionary) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = 1.0
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var span: Array[HitInstance] = [d]
	for e: Element in riders:
		var s := StatusInstance.new()
		s.def = e.terrain
		s.power = float(riders[e])
		s.raw = true
		span.append(s)
	for hit in span:
		hit.target = n
		hit.attacker = _attacker
		hit.schedule_index = 0
	return span


## Stage one on the live world: [param span] plus every entry it gathered.
func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _on(hits: Array, n: SkillNode) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h.target == n)


## B on three more far neighbours (degree 5): room under T for the land
## step's numbers, and nothing B primes reaches them.
func _widen() -> void:
	for i in 3:
		_w.link(_b, _w.add_node(StringName("B_far%d" % i), Vector2(30000.0 + 5000.0 * i, 0.0)))


## N and M, P's, far from A - B - C, each on three far anchors of its own
## (degree 3: T leaves room for the numbers); M's hitbox inside Burning's disc
## of [param power] around N.
func _pair(power: float) -> Array[SkillNode]:
	var disc := _fire.bands[0].go_off as DiscGoOff
	var n := _w.add_node(&"N", Vector2(0.0, 40000.0))
	var m := _w.add_node(&"M")
	m.global_position = n.global_position \
			+ Vector2(disc.disc_radius(power, n.radius) * 0.5 + m.radius, 0.0)
	for x: SkillNode in [n, m]:
		for i in 3:
			var anchor := _w.add_node(StringName("%s_anchor%d" % [x.name, i]),
					x.global_position + Vector2(5000.0 * i, 20000.0))
			_w.link(x, anchor)
	_w.allocate(_holder, [n, m])
	await get_tree().process_frame
	return [n, m]


func test_land_three_catalyst_and_a_two_heat_hit_give_five_heat() -> void:
	_widen()
	assert_gte(_t(), 5, "fixture: B's T holds 5 Heat inert")
	_plant(3)
	_land(_hit_on(_b, {_fire: 2}))
	assert_eq(_node.terrain_t(), 5, "the hit's 2 Heat plus the 3 Catalyst converted")
	assert_eq(_store(), 0, "the row ends at 0")


func test_land_cold_and_charge_convert_the_same_way() -> void:
	_widen()
	assert_gte(_t(), 5, "fixture: B's T holds 5 Cold and 5 Charge inert")
	_plant(3)
	_land(_hit_on(_b, {_ice: 2}))
	assert_eq(_node.terrain_t(), -5, "Cold: the hit's 2 plus the 3 converted")
	assert_eq(_store(), 0, "Cold takes the whole store")
	_put(0, 0)
	_plant(3)
	_land(_hit_on(_b, {_lightning: 2}))
	assert_eq(_node.charge(), 5, "a hit carrying only Charge converts the store to Charge")
	assert_eq(_node.terrain_t(), 0, "and no Heat: the primary element plays no part")
	assert_eq(_store(), 0, "Charge takes the whole store")


func test_land_a_hit_with_no_terrain_rider_leaves_catalyst_alone() -> void:
	_widen()
	_plant(3)
	_land(_hit_on(_b, {}))
	assert_eq(_store(), 3, "no Heat, Cold or Charge landed: the store stays")
	assert_eq(_node.terrain_t(), 0, "and no Heat moves")
	assert_eq(_node.charge(), 0, "and no Charge")


func test_land_the_split_one_to_two() -> void:
	_widen()
	assert_gte(_t(), 4, "fixture: B's T holds 4 Charge inert")
	_plant(3)
	_land(_hit_on(_b, {_fire: 1, _lightning: 2}))
	assert_eq(_node.terrain_t(), 2, "1 Heat landed and 1 converted")
	assert_eq(_node.charge(), 4, "2 Charge landed and 2 converted")
	assert_eq(_store(), 0, "the row ends at 0")


func test_land_the_split_hands_the_leftover_to_the_largest_remainder() -> void:
	_widen()
	assert_gte(_t(), 5, "fixture: B's T holds 5 Charge inert")
	_plant(5)
	_land(_hit_on(_b, {_fire: 1, _lightning: 2}))
	assert_eq(_node.terrain_t(), 3, "1 Heat landed and 2 converted")
	assert_eq(_node.charge(), 5, "2 Charge landed and 3 converted")
	assert_eq(_store(), 0, "the row ends at 0")


func test_land_a_tied_leftover_stays_catalyst() -> void:
	_widen()
	assert_gte(_t(), 2, "fixture: B's T holds 2 of each inert")
	_plant(3)
	_land(_hit_on(_b, {_fire: 1, _lightning: 1}))
	assert_eq(_node.terrain_t(), 2, "1 Heat landed and 1 converted")
	assert_eq(_node.charge(), 2, "1 Charge landed and 1 converted")
	assert_eq(_store(), 1, "the tied leftover stays Catalyst")
	_put(0, 0)
	_land(_hit_on(_b, {_fire: 1, _lightning: 1}))
	assert_eq(_node.terrain_t(), 1, "1 Catalyst over a tie converts nothing: only the hit's Heat")
	assert_eq(_node.charge(), 1, "and only the hit's Charge")
	assert_eq(_store(), 1, "the 1 stays")


func test_land_the_ratio_scales_the_result() -> void:
	_widen()
	assert_gte(_t(), 8, "fixture: B's T holds 8 Heat inert")
	_def.ratio_out = 2
	_plant(3)
	_land(_hit_on(_b, {_fire: 2}))
	assert_eq(_node.terrain_t(), 8, "the hit's 2 Heat plus 3 Catalyst at 1 : 2")
	assert_eq(_store(), 0, "the row ends at 0")


func test_land_converted_stacks_count_toward_the_hits_own_priming() -> void:
	var pair: Array[SkillNode] = await _pair(1.0)
	var n := pair[0]
	var m := pair[1]
	var nc := CombatWorld.live().combat_for(n)
	var t := nc.terrain_threshold()
	assert_gte(t, 4, "fixture: N's T leaves room for T - 4")
	nc.add_terrain(_fire, t - 4)
	var bare := _land(_hit_on(n, {_fire: 2}))
	assert_eq(nc.terrain_t(), t - 2, "with no Catalyst the hit stays under T")
	assert_eq(_on(bare, m).size(), 0, "and does not set off")
	nc.add_terrain(_fire, -2)
	nc.apply_status(_def, 3.0)
	var hits := _land(_hit_on(n, {_fire: 2}))
	assert_gt(_on(hits, m).size(), 0, "the 3 converted take N to T + 1: it sets off within the same hit")
	assert_eq(int(nc.get_status_power(_def.id)), 0, "the row ends at 0")


func test_land_a_copys_heat_rider_converts_the_reached_nodes_catalyst() -> void:
	var pair: Array[SkillNode] = await _pair(1.0)
	var n := pair[0]
	var m := pair[1]
	var nc := CombatWorld.live().combat_for(n)
	var mc := CombatWorld.live().combat_for(m)
	var disc := _fire.bands[0].go_off as DiscGoOff
	var rider := ceili(2.0 * disc.share)
	assert_gte(mc.terrain_threshold(), rider + 3, "fixture: M stays inert after the copy")
	nc.add_terrain(_fire, nc.terrain_threshold() - 1)
	mc.apply_status(_def, 3.0)
	var hits := _land(_hit_on(n, {_fire: 2}))
	assert_gt(_on(hits, m).size(), 0, "fixture: N's disc reached M")
	assert_eq(mc.terrain_t(), rider + 3, "the copy's Heat rider plus M's 3 Catalyst converted")
	assert_eq(int(mc.get_status_power(_def.id)), 0, "copies are hits: M's row is taken")


# ── Acceptance 2: the settle routine called directly ─────────────────────────


func test_heat_raised_past_t_by_the_settle_converts_the_whole_store_into_heat() -> void:
	_put(_t() - 1, 0)
	_plant(3)
	_settle(2)
	assert_eq(_node.terrain_t(), _t() + 1 + 3, "T + 1 from the flow, + 3 converted")
	assert_eq(_store(), 0, "the whole store went")


func test_heat_that_stays_at_t_converts_nothing() -> void:
	_put(_t() - 2, 0)
	_plant(3)
	_settle(2)
	assert_eq(_node.terrain_t(), _t(), "at T, not past it")
	assert_eq(_store(), 3, "flow below T never converts")


func test_heat_on_an_already_primed_node_converts_nothing_more() -> void:
	_put(_t() + 1, 0)
	_plant(3)
	_settle(1)
	assert_eq(_node.terrain_t(), _t() + 2, "no crossing, no conversion")
	assert_eq(_store(), 3, "the row stays")


func test_cold_crossing_into_frozen_converts_into_cold() -> void:
	_put(-(_t() - 1), 0)
	_plant(3)
	_settle(-2)
	assert_eq(_node.terrain_t(), -(_t() + 1 + 3), "T + 1 Cold from the flow, + 3 converted")
	assert_eq(_store(), 0, "the whole store went")


func test_charge_crossing_into_shocked_converts_into_charge() -> void:
	_put(0, _t() - 1)
	_plant(3)
	_settle(0, 2)
	assert_eq(_node.charge(), _t() + 1 + 3, "T + 1 Charge, + 3 converted")
	assert_eq(_store(), 0, "the whole store went")


func test_a_landing_that_splits_and_primes_converts_the_leftover_at_settle() -> void:
	assert_gt(_t(), 2, "fixture: the landing's Charge stays under T")
	_put(_t() - 1, 0)
	_plant(3)
	var landing := {_heat_id: 1, _charge_id: 1}
	var out := _def.convert(_node, landing)
	assert_eq(out, {_heat_id: 1, _charge_id: 1}, "at land: 1 Heat and 1 Charge")
	assert_eq(_store(), 1, "the tied 1 is left")
	_settle(1 + int(out.get(_heat_id, 0)), 1 + int(out.get(_charge_id, 0)))
	assert_eq(_node.terrain_t(), _t() + 2, "T + 1 from the landing, + the 1 left at settle")
	assert_eq(_node.charge(), 2, "Charge did not cross; no more of it")
	assert_eq(_store(), 0, "the row ends at 0")


func test_two_bands_crossing_at_once_split_by_their_excess() -> void:
	# Tentative (not the owner's): the store splits over the crossed elements,
	# weighted by each one's excess past T (1 and 2 here, so 3 splits 1 : 2).
	_put(_t() - 1, _t() - 1)
	_plant(3)
	_settle(2, 3)
	assert_eq(_node.terrain_t(), _t() + 1 + 1, "Heat, excess 1: one third")
	assert_eq(_node.charge(), _t() + 2 + 2, "Charge, excess 2: two thirds")
	assert_eq(_store(), 0, "1 : 2 leaves nothing")


func test_converted_stacks_obey_the_cap_and_overflow() -> void:
	var cap := _node.terrain_cap()
	assert_gt(cap, _t(), "fixture: k × T above T")
	_put(_t() - 1, 0)
	_plant(cap)
	_settle(2)
	var heat := _node.terrain_t()
	assert_eq(heat, _t() + 1 + cap, "the conversion lands through the one writer, unclamped")
	assert_gt(Terrain.overflow(heat, cap), 0, "the stacks past k × T are overflow, which burns off at decay (#1795)")
	var band := _node.terrain_band(_fire)
	assert_true(band != null and band.at_cap, "the node reads the cap band")


func test_the_seat_carries_one_prime_conversion_per_catalyst_def_in_the_roster() -> void:
	var roster := StatusRoster.shared()
	var before := _prime_readers().size()
	roster.statuses.append(_def)
	var readers := _prime_readers()
	assert_eq(readers.size(), before + 1, "a CatalystStatus in the roster seats one reader")
	assert_true(readers.any(func(r: TerrainSettle.PrimeConversion) -> bool: return r.def == _def), "over that def")
	_put(_t() - 1, 0)
	_plant(3)
	var batch := TerrainSettle.Batch.new()
	batch.add_net_t(_node, 2)
	TerrainSettle.commit(batch)
	assert_eq(_node.terrain_t(), _t() + 1 + 3, "commit() runs the seat: the store converts")
	assert_eq(_store(), 0, "the row went")


func _prime_readers() -> Array:
	return TerrainSettle.seat().filter(
			func(r: TerrainSettle.SettleReader) -> bool: return r is TerrainSettle.PrimeConversion)


# ── Acceptance 3: the goo arrow ──────────────────────────────────────────────
# Waits for #1800 (Burning's disc) and F-a's copies: the retag / land-hook unit.


# ── Acceptance 4: the cap ────────────────────────────────────────────────────


func test_catalyst_caps_at_k_times_t() -> void:
	var cap := _node.terrain_cap()
	assert_gt(cap, 0, "fixture: an owned node has a cap")
	_plant(cap + 5)
	assert_eq(_store(), cap, "the row stops at k × T")
	_plant(1)
	assert_eq(_store(), cap, "still k × T")


func test_cap_off_leaves_the_row_to_power_max() -> void:
	_def.cap_k_times_t = false
	var cap := _node.terrain_cap()
	_plant(cap + 5)
	assert_eq(_store(), cap + 5, "power_max 0 is uncapped")


# ── Acceptance 1 (centre), 3, 4 and 4b: the shipped def ──────────────────────

const _CATALYST_TRES := preload("res://effects/status/catalyst.tres")
const _POISON_TRES := preload("res://effects/status/poison.tres")


func test_the_shipped_def_is_a_catalyst_status_that_decays_per_world_turn() -> void:
	assert_true(_CATALYST_TRES is CatalystStatus, "catalyst.tres carries the CatalystStatus script")
	assert_true(_CATALYST_TRES.decay_per_world_turn, "decays on the world turn, not its holder's")


func test_a_hits_centre_landing_converts_nothing() -> void:
	var pair: Array[SkillNode] = await _burning_pair(5)
	var n := pair[0]
	var nc := CombatWorld.live().combat_for(n)
	var heat := nc.terrain_t()
	var span := _hit_on(n, {})
	var hits := _land(span)
	var centre := _on(hits, n).filter(func(h: HitInstance) -> bool: return not span.has(h))
	assert_gt(centre.size(), 0, "fixture: Burning's disc landed a centre copy on N")
	for h: HitInstance in centre:
		assert_false(h is StatusInstance and [_fire.terrain, _ice.terrain, _lightning.terrain].has((h as StatusInstance).def),
				"the centre copy carries no terrain rider")
	assert_lte(nc.terrain_t(), heat, "nothing converted: no Heat appears")


## A goo (or poison) arrow's head plus its one [param def] rider on Burning N,
## landed; what M, inside N's disc, ends holding of [param def] and what N's
## own Catalyst and Heat did.
func _goo_on_m(pair: Array[SkillNode], def: StatusDef, stacks: int) -> Dictionary:
	var n := pair[0]
	var m := pair[1]
	var nc := CombatWorld.live().combat_for(n)
	nc.add_terrain(_fire, nc.terrain_threshold() + 1 - nc.terrain_t())
	var heat := nc.terrain_t()
	var catalyst := int(nc.get_status_power(_CATALYST_TRES.id))
	var span := _hit_on(n, {})
	var s := StatusInstance.new()
	s.def = def
	s.power = float(stacks)
	s.raw = true
	s.target = n
	s.attacker = _attacker
	s.schedule_index = 0
	span.append(s)
	var hits := _land(span)
	var carried := 0.0
	for e: HitInstance in _on(hits, m):
		if e is StatusInstance and (e as StatusInstance).def == def:
			carried += (e as StatusInstance).power
	return {
		"reached_m": _on(hits, m).size() > 0,
		"added_on_m": carried,
		"catalyst_kept": int(nc.get_status_power(_CATALYST_TRES.id)) == catalyst,
		"heat_kept": nc.terrain_t() <= heat,
	}


func _burning_pair(catalyst: int = 2) -> Array[SkillNode]:
	var pair: Array[SkillNode] = await _pair(1.0)
	var nc := CombatWorld.live().combat_for(pair[0])
	nc.add_terrain(_fire, nc.terrain_threshold() + 1 - nc.terrain_t())
	if catalyst > 0:
		nc.apply_status(_CATALYST_TRES, float(catalyst))
	return pair


func test_a_goo_arrow_on_a_burning_node_sets_it_off_and_converts_nothing() -> void:
	var pair: Array[SkillNode] = await _burning_pair()
	var goo := _goo_on_m(pair, _CATALYST_TRES, 2)
	assert_true(goo.reached_m, "the Burning disc reached M: the arrow set N off like any hit")
	assert_gt(float(goo.added_on_m), 0.0, "the copy carries the Catalyst rider over the disc")
	assert_true(goo.catalyst_kept, "N's own Catalyst is neither converted nor lost")
	assert_true(goo.heat_kept, "no Heat lands: N's own Catalyst converts into none, its Heat only falls (Burning's own spend)")


## N holds no Catalyst here: go-off zero's disc reads N's own row, and a
## poison arrow sets it off where a goo arrow's own-aspect skip does not.
func test_goo_plants_the_same_stacks_as_poison_on_the_same_board() -> void:
	var pair: Array[SkillNode] = await _burning_pair(0)
	var poison := _goo_on_m(pair, _POISON_TRES, 2)
	var goo := _goo_on_m(pair, _CATALYST_TRES, 2)
	assert_gt(float(poison.added_on_m), 0.0, "fixture: poison planted on M")
	assert_eq(goo.added_on_m, poison.added_on_m, "Catalyst adds what Poison adds, stacks under both caps")


func test_catalyst_lands_only_on_allocated_nodes() -> void:
	var free := _w.add_node(&"Free", Vector2(0.0, -40000.0))
	await get_tree().process_frame
	var fc := free.get_combat()
	fc.apply_status(_CATALYST_TRES, 3.0)
	assert_eq(int(fc.get_status_power(_CATALYST_TRES.id)), 0, "an unallocated node takes none")
	_node.apply_status(_CATALYST_TRES, 3.0)
	assert_eq(int(_node.get_status_power(_CATALYST_TRES.id)), 3, "an allocated node takes it")


func test_catalyst_clears_on_dealloc() -> void:
	_node.apply_status(_CATALYST_TRES, 3.0)
	assert_eq(int(_node.get_status_power(_CATALYST_TRES.id)), 3, "fixture: planted")
	_w.allocator().force_deallocate(_b)
	assert_eq(int(_node.get_status_power(_CATALYST_TRES.id)), 0, "the row is cleared")


func test_the_row_decays_once_when_the_world_turn_closes_by_the_per_tick_rate() -> void:
	var tm: TurnManager = autofree(TurnManager.new())
	tm.entity_root = _w.graph
	add_child(tm)
	# P (holder) and Q are the two carriers; Q has no node.
	_node.apply_status(_CATALYST_TRES, 5.0)
	var rate := int((_CATALYST_TRES.decay as FlatDecay).per_tick)
	assert_gt(rate, 0, "fixture: the def decays")
	assert_gt(5 - rate, 0, "fixture: N above the rate")
	tm.start_turn(_holder)
	assert_eq(TurnManager.world_turn_period(2, tm.world_clock), 2, "PER_CARRIER: a world turn per 2 turn ends")
	tm.end_turn()
	assert_eq(_store_of(_CATALYST_TRES), 5, "after the first played turn end the row is unchanged")
	tm.end_turn()
	assert_eq(_store_of(_CATALYST_TRES), 5 - rate, "after the second, down by the per-tick decay, once")


func test_the_loss_per_world_turn_is_at_most_the_fire_bands() -> void:
	var rate := (_CATALYST_TRES.decay as FlatDecay).per_tick
	var band := _fire.bands[0] as ElementBand
	assert_lte(rate, float(band.decay_per_world_turn), "Catalyst fades no faster than the Fire band")


func _store_of(def: StatusDef) -> int:
	return int(_node.get_status_power(def.id))


