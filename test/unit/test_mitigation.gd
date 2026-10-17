extends GutTest

## Mitigation — damage formula `max(min_damage_taken, raw - armor)`, TRUE bypass,
## zero-raw passthrough, and (since #4) node-local armor actually reaching it.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _raw(amount: float, type: int = DamageInstance.Type.PHYSICAL) -> DamageInstance:
	var d := DamageInstance.new()
	d.amount = amount
	d.type = type as DamageInstance.Type
	return d


# ── The formula itself ──────────────────────────────────────────────────────

func test_no_armor_no_floor_passes_through() -> void:
	assert_almost_eq(Mitigation.compute(7.0, 0.0, 0.0), 7.0, 0.001)


func test_armor_reduces_flat() -> void:
	assert_almost_eq(Mitigation.compute(10.0, 3.0, 0.0), 7.0, 0.001)


func test_floor_applies_when_armor_exceeds_raw() -> void:
	assert_almost_eq(Mitigation.compute(5.0, 20.0, 3.0), 3.0, 0.001)


func test_zero_raw_stays_zero_even_with_floor() -> void:
	assert_almost_eq(Mitigation.compute(0.0, 0.0, 3.0), 0.0, 0.001)


func test_negative_floor_allows_healing_via_overkill_armor() -> void:
	# raw - armor = 3 - 10 = -7; max(-5, -7) = -5 → "damage" is negative (heal).
	assert_almost_eq(Mitigation.compute(3.0, 10.0, -5.0), -5.0, 0.001)


## Negative armor pushes damage ABOVE raw — the Ninja debuff aura's mechanic.
## But the floor masks it until `raw - armor` clears `min_damage_taken`.
func test_negative_armor_amplifies_but_floor_masks_small_hits() -> void:
	# The brief's worked example: raw 1, armor -1. max(3, 2) = 3, not 2.
	assert_almost_eq(Mitigation.compute(1.0, -1.0, 3.0), 3.0, 0.001)
	# Deeper into the constellation (armor -3) it clears the floor.
	assert_almost_eq(Mitigation.compute(1.0, -3.0, 3.0), 4.0, 0.001)
	# A real hit shows the amplification directly.
	assert_almost_eq(Mitigation.compute(5.0, -3.0, 3.0), 8.0, 0.001)


# ── Node-local reads (the bug bunker_addon sat on) ──────────────────────────

func _owned_node() -> SkillNode:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "D"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var node: SkillNode = _NODE_SCENE.instantiate()
	autofree(node)
	add_child(ent)
	add_child(node)
	node.owned_by = ent
	return node


func test_true_damage_bypasses_armor_and_floor() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 99.0
	node.owned_by.stat_board.min_damage_taken.base_value = 99.0
	assert_almost_eq(Mitigation.apply(_raw(7.0, DamageInstance.Type.TRUE), node), 7.0, 0.001)


func test_entity_armor_is_read_through_the_node() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 3.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0
	assert_almost_eq(Mitigation.apply(_raw(10.0), node), 7.0, 0.001)


## The regression this whole fix exists for: a node-local `armor` modifier — what
## bunker_addon grants — must reduce damage. It never did before #4.
func test_node_local_armor_reduces_damage() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 0.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0
	assert_almost_eq(Mitigation.apply(_raw(10.0), node), 10.0, 0.001)

	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = 5.0
	node.add_local_modifier(m)

	assert_almost_eq(Mitigation.apply(_raw(10.0), node), 5.0, 0.001,
		"node-local armor must reach the damage formula")

	node.remove_local_modifier(m)
	assert_almost_eq(Mitigation.apply(_raw(10.0), node), 10.0, 0.001)


## Same, driven through the real bunker_addon scene rather than a hand-built
## modifier — guards the authored .tscn against a silent field strip.
func test_bunker_addon_actually_armors_its_carrier() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 0.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0

	var addon: SkillNodeAddon = preload("res://skill_node/addons/defs/bunker_addon.tscn").instantiate()
	assert_eq(addon.local_modifiers.size(), 3, "bunker_addon lost one of its authored modifiers")
	node.add_child(addon)
	await get_tree().process_frame

	assert_almost_eq(Mitigation.apply(_raw(10.0), node), 5.0, 0.001,
		"bunker_addon's +5 node-local armor must reduce a 10-damage hit to 5")


## Node-local min_damage_taken composes too — a per-node floor override.
func test_node_local_floor_applies() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 20.0
	node.owned_by.stat_board.min_damage_taken.base_value = 3.0
	assert_almost_eq(Mitigation.apply(_raw(5.0), node), 3.0, 0.001)


# ── HitInstance.kind reclassification (#381) ────────────────────────────────
## SkillNode.take_damage reclassifies a DamageInstance to HitInstance.Kind.HEAL
## when the post-Mitigation effective amount underflows below zero (a
## Bulwark-style min_damage_taken floor deep enough to overshoot armor —
## test_negative_floor_allows_healing_via_overkill_armor above pins the
## formula; these pin take_damage's classification + HP effect on top of it).

func test_take_damage_stays_damage_kind_when_effective_is_zero() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 10.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0
	var hit := _raw(10.0)  # 10 - 10 armor = 0, exactly at the floor
	node.take_damage(hit.amount, hit)
	assert_eq(hit.kind, HitInstance.Kind.DAMAGE,
		"a real hit that soaks to exactly 0 is still DAMAGE, not HEAL")


func test_take_damage_reclassifies_to_heal_on_negative_effective() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	# First, deal real damage under a real defense config so HP has room for
	# the heal-flip below to actually show.
	node.owned_by.stat_board.armor.base_value = 0.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0
	node.take_damage(5.0, null)
	var hp_before := node.get_current_hp()
	assert_true(hp_before < node.get_max_hp(), "fixture: node must be damaged before the flip")

	# Bulwark-style underflow: 3 - 10 armor = -7, floored at -5.
	node.owned_by.stat_board.armor.base_value = 10.0
	node.owned_by.stat_board.min_damage_taken.base_value = -5.0
	var hit := _raw(3.0)
	node.take_damage(hit.amount, hit)

	assert_eq(hit.kind, HitInstance.Kind.HEAL,
		"3 - 10 armor = -7, floored at -5 → negative effective reclassifies to HEAL")
	assert_true(node.get_current_hp() > hp_before,
		"the negative-effective 'hit' must actually raise HP like a heal")
	assert_almost_eq(hit.effective_amount, node.get_current_hp() - hp_before, 0.001,
		"effective_amount is the actual clamped delta's magnitude, always positive")


## Regression: effective_amount's contract for ordinary DAMAGE must stay the
## post-mitigation number, not the post-soak HP delta — an overkill hit still
## has to report the full mitigated amount (so a killing blow's floater
## doesn't under-report to whatever HP happened to be left).
func test_take_damage_effective_amount_is_mitigated_not_soaked_on_overkill() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 0.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0
	node.take_damage(node.get_max_hp() - 3.0, null)
	assert_almost_eq(node.get_current_hp(), 3.0, 0.001, "fixture: node left at 3 HP")

	var hit := _raw(10.0)  # overkill: only 3 HP is left to soak
	node.take_damage(hit.amount, hit)

	assert_eq(hit.kind, HitInstance.Kind.DAMAGE)
	assert_almost_eq(node.get_current_hp(), 0.0, 0.001)
	assert_almost_eq(hit.effective_amount, 10.0, 0.001,
		"effective_amount reports the full mitigated hit, not the 3 HP actually soaked")


# ── Armor pierce: the attacker's pipeline over the defender's FINAL armor ────
# Terms are built from real StatModifiers through ModifierBins, so the bin
# order (ADD_BASE, then INCREASE × MULTIPLY, then ADD_BONUS; SET wins) is what
# is tested — never a hand-filled FoldTerms.

func _mod(op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor_pierce"
	m.operation = op
	m.value = value
	return m


func _pierce(mods: Array) -> FoldTerms:
	var bins := ModifierBins.new()
	for m in mods:
		bins.add(m, null)
	var sources: Array[ModifierBins] = [bins]
	return ModifierBins.resolve(sources)


func test_pierce_multiply_halves_armor_and_floors_to_whole() -> void:
	# armor 5 × 0.5 = 2.5 → whole 2 → 10 − 2
	assert_almost_eq(Mitigation.compute(10.0, 5.0, 0.0, _pierce([_mod(StatModifier.Operation.MULTIPLY, 0.5)])), 8.0, 0.001)


func test_pierce_add_base_lowers_armor() -> void:
	assert_almost_eq(Mitigation.compute(10.0, 5.0, 0.0, _pierce([_mod(StatModifier.Operation.ADD_BASE, -3.0)])), 8.0, 0.001)


func test_pierce_stops_at_zero_never_inverts() -> void:
	# (5 × 0.5) − 5 = −2.5 → clamped 0, never a bigger hit
	var p := _pierce([_mod(StatModifier.Operation.MULTIPLY, 0.5), _mod(StatModifier.Operation.ADD_BONUS, -5.0)])
	assert_almost_eq(Mitigation.compute(10.0, 5.0, 0.0, p), 10.0, 0.001)


func test_pierce_leaves_negative_armor_untouched() -> void:
	assert_almost_eq(Mitigation.compute(10.0, -4.0, 0.0, _pierce([_mod(StatModifier.Operation.MULTIPLY, 0.5)])), 14.0, 0.001)
	assert_almost_eq(Mitigation.compute(10.0, -4.0, 0.0, _pierce([_mod(StatModifier.Operation.ADD_BASE, -3.0)])), 14.0, 0.001)


func test_pierce_on_zero_armor_is_zero() -> void:
	assert_almost_eq(Mitigation.compute(10.0, 0.0, 0.0, _pierce([_mod(StatModifier.Operation.ADD_BASE, -3.0)])), 10.0, 0.001)


func test_pierce_set_zero_ignores_armor() -> void:
	assert_almost_eq(Mitigation.compute(10.0, 5.0, 0.0, _pierce([_mod(StatModifier.Operation.SET, 0.0)])), 10.0, 0.001)


func test_null_pierce_is_identity() -> void:
	assert_almost_eq(Mitigation.compute(10.0, 5.0, 0.0, null), 5.0, 0.001)


func test_floor_still_wins_after_pierce() -> void:
	var p := _pierce([_mod(StatModifier.Operation.ADD_BASE, -3.0)])
	assert_almost_eq(Mitigation.compute(4.0, 5.0, 3.0, p), 3.0, 0.001, "max(floor 3, 4 − 2)")
	assert_almost_eq(Mitigation.compute(4.0, 5.0, 0.0, p), 2.0, 0.001)


## Two pipelines, not merged bins: the defender's armor folds to its FINAL
## value (base 4, +50% INC, +2 BONUS → 8) and the pierce then folds THAT. A
## refactor that merges the pierce into the defender's armor bins lands the
## other column (3 / 6 / 5) and reds here.
func test_pierce_folds_the_defenders_final_armor() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.owned_by.stat_board.armor.base_value = 4.0
	node.owned_by.stat_board.min_damage_taken.base_value = 0.0
	var inc := StatModifier.new()
	inc.stat_id = &"armor"
	inc.operation = StatModifier.Operation.INCREASE
	inc.value = 50.0
	node.add_local_modifier(inc)
	var bon := StatModifier.new()
	bon.stat_id = &"armor"
	bon.operation = StatModifier.Operation.ADD_BONUS
	bon.value = 2.0
	node.add_local_modifier(bon)
	assert_eq(int(node.get_local_value(&"armor")), 8, "fixture: displayed armor 8")
	var rows := [
		[_mod(StatModifier.Operation.ADD_BASE, -3.0), 5.0],
		[_mod(StatModifier.Operation.INCREASE, -50.0), 4.0],
		[_mod(StatModifier.Operation.MULTIPLY, 0.5), 4.0],
		[_mod(StatModifier.Operation.SET, 0.0), 0.0],
	]
	for row in rows:
		var hit := _raw(20.0)
		hit.armor_pierce = _pierce([row[0]])
		assert_almost_eq(Mitigation.apply(hit, node), 20.0 - row[1], 0.001,
			"pierce %s on final armor 8 → effective armor %s" % [row[0].operation, row[1]])


## The producer's stamp: board terms (node-local) overlaid with the producer's
## own modifiers; uses_board off with nothing authored → null.
func test_pierce_terms_overlay_board_with_producer_mods() -> void:
	var node := _owned_node()
	await get_tree().process_frame
	node.add_local_modifier(_mod(StatModifier.Operation.ADD_BASE, -3.0))
	var no_mods: Array[StatModifier] = []
	var half: Array[StatModifier] = [_mod(StatModifier.Operation.MULTIPLY, 0.5)]
	var board_only: FoldTerms = Mitigation.pierce_terms(node.get_combat(), true, no_mods)
	assert_not_null(board_only, "a node-local armor_pierce modifier reaches the terms")
	assert_almost_eq(board_only.fold(8.0), 5.0, 0.001)
	assert_almost_eq(Mitigation.pierce_terms(node.get_combat(), true, half).fold(8.0), 2.5, 0.001,
		"(8 − 3) × 0.5")
	assert_null(Mitigation.pierce_terms(node.get_combat(), false, no_mods),
		"uses_board_pierce off and nothing authored stamps null even with board pierce")
	assert_almost_eq(Mitigation.pierce_terms(node.get_combat(), false, half).fold(8.0), 4.0, 0.001,
		"producer-only: the board's −3 is ignored")
