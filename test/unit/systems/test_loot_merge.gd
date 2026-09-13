extends GutTest

## Entity.absorb_core_modifier (#775) — the loot merge verb. SkillDust pickup
## (SkillDustAddon._grant_mod) routes a looted grant through here instead of
## Entity.grant_core_modifier: an EQUIVALENT existing grant (same stat_id +
## operation + formula, ignoring `value` — StatModifierCodec.merge_key) adds
## coefficients into ONE modifier instead of holding another copy.
##
## Also covers the late-join amendment (StatBoard.read_dict pre-syncing the
## register from the wire BEFORE Stat._reconcile_modifiers runs), at the
## StatBoard/Entity level directly — a full EntitySnapshot round trip lives
## outside this drone's fence (network/ is not owned by #775/#774).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")

var _entity: Entity


func before_each() -> void:
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_entity.core_class = _BALANCED
	add_child_autofree(_entity)
	await get_tree().process_frame  # _ready -> initialize(): board dup, apply_intrinsics, core_class.apply


func _mk_mod(id: StringName, op: StatModifier.Operation, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = v
	return m


func _find_intrinsic(id: StringName) -> StatModifier:
	for m in _entity.stat_board.intrinsic_modifiers:
		if m.stat_id == id:
			return m
	return null


# ── Merge into an intrinsic ──────────────────────────────────────────────────

func test_absorb_merges_into_a_matching_intrinsic_without_appending() -> void:
	# default_entity_board.tres: wisdom -> xp_per_turn, ADD_BASE, value 1.0,
	# RatioFormula(wisdom, 5) — see .claude/rules/stats-system.md's table.
	var loot := _mk_mod(&"xp_per_turn", StatModifier.Operation.ADD_BASE, 1.0)
	var f := RatioFormula.new()
	f.source_stat_id = &"wisdom"
	f.divisor = 5.0
	loot.formula = f

	var before := _entity.core_modifiers.size()
	_entity.absorb_core_modifier(loot)

	assert_eq(_entity.core_modifiers.size(), before, "nothing appended — it merged into the intrinsic")
	var intrinsic := _find_intrinsic(&"xp_per_turn")
	assert_not_null(intrinsic)
	assert_eq(intrinsic.value, 2.0, "authored 1.0 + looted 1.0 = 2.0, added in place")


func test_absorb_with_a_mismatched_formula_divisor_appends_instead_of_merging() -> void:
	# #775 amendment: the merge key includes the formula dict, so a divisor
	# mismatch (the still-live spell_damage-style parity gap) silently appends
	# rather than merging — pinned so that's visible behaviour, not a surprise.
	var loot := _mk_mod(&"xp_per_turn", StatModifier.Operation.ADD_BASE, 1.0)
	var f := RatioFormula.new()
	f.source_stat_id = &"wisdom"
	f.divisor = 10.0  # mismatched vs. the board's own /5 rule
	loot.formula = f

	var before := _entity.core_modifiers.size()
	_entity.absorb_core_modifier(loot)

	assert_eq(_entity.core_modifiers.size(), before + 1,
			"different formula dict -> appends, does not merge")
	var intrinsic := _find_intrinsic(&"xp_per_turn")
	assert_eq(intrinsic.value, 1.0, "the intrinsic itself is untouched")


func test_absorb_merges_a_static_modifier_too() -> void:
	var first := _mk_mod(&"armor", StatModifier.Operation.ADD_BASE, 5.0)
	_entity.absorb_core_modifier(first)
	assert_true(_entity.core_modifiers.has(first), "no match yet -> ordinary append")

	var second := _mk_mod(&"armor", StatModifier.Operation.ADD_BASE, 5.0)
	var before := _entity.core_modifiers.size()
	_entity.absorb_core_modifier(second)

	assert_eq(_entity.core_modifiers.size(), before, "merged, not appended")
	assert_eq(first.value, 10.0, "+5 twice = +10 once, on the SAME instance")


func test_absorb_never_merges_a_composite() -> void:
	var pack_a := CompositeStatModifier.new()
	pack_a.loots_as_unit = true
	pack_a.children = [_mk_mod(&"deallocation_points", StatModifier.Operation.ADD_BASE, 2.0)]
	var pack_b := CompositeStatModifier.new()
	pack_b.loots_as_unit = true
	pack_b.children = [_mk_mod(&"deallocation_points", StatModifier.Operation.ADD_BASE, 2.0)]

	var before := _entity.core_modifiers.size()
	_entity.absorb_core_modifier(pack_a)
	_entity.absorb_core_modifier(pack_b)

	assert_eq(_entity.core_modifiers.size(), before + 2, "composites always append, never merge")


func test_no_match_appends_through_the_ordinary_grant() -> void:
	var loot := _mk_mod(&"movement_points", StatModifier.Operation.ADD_BASE, 1.0)
	var before := _entity.core_modifiers.size()
	_entity.absorb_core_modifier(loot)
	assert_eq(_entity.core_modifiers.size(), before + 1)
	assert_true(_entity.core_modifiers.has(loot))


# ── The event contract (#775 decision 9) ─────────────────────────────────────

func test_merge_emits_stat_modifier_changed_once_with_the_merged_target() -> void:
	var first := _mk_mod(&"armor", StatModifier.Operation.ADD_BASE, 5.0)
	_entity.absorb_core_modifier(first)

	var captured: Array = []
	var handler := func(e: Entity, m: StatModifier, k: ModifierBinding.Kind, added: bool) -> void:
		captured.append([e, m, k, added])
	Events.stat_modifier_changed.connect(handler)
	var second := _mk_mod(&"armor", StatModifier.Operation.ADD_BASE, 5.0)
	_entity.absorb_core_modifier(second)
	Events.stat_modifier_changed.disconnect(handler)

	assert_eq(captured.size(), 1, "one event for the merge, not one per leaf")
	assert_eq(captured[0][0], _entity)
	assert_eq(captured[0][1], first, "carries the MERGED target")
	assert_ne(captured[0][1], second, "never the just-absorbed copy")
	assert_eq(captured[0][2], ModifierBinding.Kind.CORE)
	assert_true(captured[0][3])


# ── Privatising a file-backed class-template grant (#775 decision 6) ────────

func test_absorb_privatizes_a_file_backed_class_grant_before_merging() -> void:
	# BalancedCore's core_class.apply() already granted the SAME shared
	# +10 Wisdom .tres subresource (mod_wis) into core_modifiers — no
	# per-entry duplication, per #377.
	var shared_wis: StatModifier = null
	for m in _entity.core_modifiers:
		if m.stat_id == &"wisdom" and m.operation == StatModifier.Operation.ADD_BASE and m.formula == null:
			shared_wis = m
			break
	assert_not_null(shared_wis, "precondition: BalancedCore granted +10 Wisdom")
	assert_false(shared_wis.resource_path.is_empty(), "precondition: it's the shared .tres instance")

	var loot := _mk_mod(&"wisdom", StatModifier.Operation.ADD_BASE, 10.0)
	_entity.absorb_core_modifier(loot)

	assert_eq(shared_wis.value, 10.0, "the SHARED original is never mutated")
	assert_eq(_entity.core_modifiers.find(shared_wis), -1,
			"the shared instance is no longer in the register")
	var merged: StatModifier = null
	for m in _entity.core_modifiers:
		if m.stat_id == &"wisdom" and m.operation == StatModifier.Operation.ADD_BASE and m.formula == null:
			merged = m
	assert_not_null(merged, "a private duplicate replaced it in the register")
	assert_eq(merged.value, 20.0, "10 (class) + 10 (loot) = 20, on the duplicate")
	assert_true(merged.resource_path.is_empty(), "the duplicate is unshared")
	assert_eq(_entity.core_modifiers.size(), 1 + 5, "register size unchanged by the swap (still one +10 Wisdom slot)")


# ── Late-join register re-point (#775 amendment) ─────────────────────────────

func test_sync_register_from_wire_keeps_the_register_as_the_bound_instance() -> void:
	# Simulate a wire snapshot where a remote merge moved this board's
	# xp_per_turn intrinsic from 1.0 to 1.25 BEFORE it reaches this board.
	var board: EntityStatBoard = _BOARD.duplicate(true)
	board.apply_intrinsics()
	var xp_per_turn := board.get_stat(&"xp_per_turn")
	assert_not_null(xp_per_turn)

	var wire := board.to_dict()
	var mods: Array = (wire[String(&"xp_per_turn")] as Dictionary)["mods"]
	assert_eq(mods.size(), 1, "precondition: exactly the one board intrinsic")
	(mods[0] as Dictionary)["value"] = 1.25

	board.read_dict(wire)

	var register_entry: StatModifier = null
	for m in board.intrinsic_modifiers:
		if m.stat_id == &"xp_per_turn":
			register_entry = m
			break
	assert_not_null(register_entry)
	assert_eq(register_entry.value, 1.25, "the register's OWN entry carries the merged value")
	assert_true(xp_per_turn.has_modifier(register_entry),
			"the register entry IS the bound instance — reconcile kept it, minted nothing fresh")


func test_sync_register_from_wire_repoints_core_modifiers_through_entity() -> void:
	# Same mechanism, one layer down: Entity.core_modifiers lives off-board, so
	# StatBoard.read_dict tells it via `restoring` (Entity._on_stat_board_restoring).
	var wire := _entity.stat_board.to_dict()
	var mods: Array = (wire[String(&"wisdom")] as Dictionary)["mods"]
	var target_dict: Dictionary = {}
	for md in mods:
		if float((md as Dictionary).get("value", 0.0)) == 10.0 and (md as Dictionary).get("formula") == null:
			target_dict = md
			break
	assert_false(target_dict.is_empty(), "precondition: BalancedCore's +10 Wisdom is on the wire")
	target_dict["value"] = 12.0  # simulate a remote merge: +10 -> +12

	_entity.stat_board.read_dict(wire)

	var wisdom_stat := _entity.stat_board.get_stat(&"wisdom")
	var found := false
	for m in _entity.core_modifiers:
		if m.stat_id == &"wisdom" and wisdom_stat.has_modifier(m) and m.value == 12.0:
			found = true
	assert_true(found, "core_modifiers' entry for that key IS the bound (merged) instance")
