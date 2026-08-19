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

	var addon: SkillNodeAddon = preload("res://skill_node/addons/bunker_addon.tscn").instantiate()
	assert_eq(addon.local_modifiers.size(), 2, "bunker_addon lost one of its authored modifiers")
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
