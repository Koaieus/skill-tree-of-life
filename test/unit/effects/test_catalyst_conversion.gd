extends GutTest

## #1801 C — the Catalyst core, additive. [CatalystStatus]'s pure split
## [method CatalystStatus.converted], its ratio and its k × T cap; the
## row-taking [method CatalystStatus.convert] the land step and the settle seat
## share; and the prime conversion seated in the settle routine
## ([TerrainSettle.PrimeConversion]). Acceptance 1 (through `converted()` and
## `convert()` alone), 2 (the settle routine called directly) and 4's cap.
## Every def is built here: `catalyst.tres` is the retag unit's, so no current
## behaviour moves. Fixture: A - B - C, B owned (graph degree 2); T and the cap
## are read off B, never a literal.

var _w: TestWorld
var _node: NodeCombat
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
	var a := _w.add_node(&"A")
	var b := _w.add_node(&"B")
	var c := _w.add_node(&"C")
	_w.link(a, b)
	_w.link(b, c)
	b.owned_by = holder
	holder.navigator.mirror_add(b)
	await get_tree().process_frame
	_node = b.get_combat()
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
# Waits for F-a (#1799, attack/outcome/hit_gather.gd): the land step calls
# CatalystStatus.convert(node, landing) and folds its output into the land batch
# before the terrain write. Its cases (the hit's own primed-ness and power, a
# centre landing, a copy's rider) are the land-hook unit's.


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


# Acceptance 4's "lands only on allocated nodes, clears on dealloc" and 4b's
# numbers read catalyst.tres: the retag unit's.
