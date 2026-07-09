extends GutTest

## Effect substrate (#4): hook bucketing + dispatch, the grant ledger, and the
## AllocationSystem wiring that finally makes node-borne effects live.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


## Records every hook it receives. Implements a strict subset of HOOKS, so
## bucketing has something to get wrong.
class SpyEffect extends Effect:
	var turn_starts: int = 0
	var allocations: Array[SkillNode] = []
	var core_moves: int = 0

	func _on_turn_start(_ctx: EffectContext) -> void:
		turn_starts += 1

	func _on_node_allocated(_ctx: EffectContext, node: SkillNode, _forced: bool) -> void:
		allocations.append(node)

	func _on_core_moved(_ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
		core_moves += 1


## Implements nothing. Must never be dispatched to.
class InertEffect extends Effect:
	pass


class DamageSpyEffect extends Effect:
	var hits: Array[float] = []

	func _on_node_damaged(_ctx: EffectContext, _node: SkillNode, amount: float) -> void:
		hits.append(amount)


## Grants a node-local modifier mid-life, from a hook rather than at boundary.
class MidLifeEffect extends Effect:
	func _on_turn_start(ctx: EffectContext) -> void:
		var m := StatModifier.new()
		m.stat_id = &"armor"
		m.operation = StatModifier.Operation.ADD_BONUS
		m.value = 7.0
		ctx.grant(m, ctx.source_node)


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as StatBoard
	return ent


func _make_node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	autofree(n)
	return n


func _mod(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


# ── Hook declaration + bucketing ────────────────────────────────────────────

func test_implemented_hooks_reports_only_declared_ones() -> void:
	var spy := SpyEffect.new()
	var hooks := spy.implemented_hooks()
	assert_true(hooks.has(&"_on_turn_start"))
	assert_true(hooks.has(&"_on_node_allocated"))
	assert_true(hooks.has(&"_on_core_moved"))
	assert_false(hooks.has(&"_on_level_up"), "undeclared hook must not be bucketed")
	assert_eq(hooks.size(), 3)


func test_inert_effect_declares_no_hooks() -> void:
	assert_eq(InertEffect.new().implemented_hooks().size(), 0)


func test_dispatch_reaches_only_implementing_effects() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var spy := SpyEffect.new()
	ent.grant_effect(spy)
	ent.grant_effect(InertEffect.new())  # must not explode on dispatch

	ent.dispatch(&"_on_turn_start")
	ent.dispatch(&"_on_turn_start")
	assert_eq(spy.turn_starts, 2)

	# A hook nobody implements is a no-op, not an error.
	ent.dispatch(&"_on_killing_blow", [ent])
	assert_eq(spy.turn_starts, 2)


func test_revoked_effect_stops_receiving_hooks() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var spy := SpyEffect.new()
	var inst := ent.grant_effect(spy)
	ent.dispatch(&"_on_turn_start")
	ent.revoke_effect(inst)
	ent.dispatch(&"_on_turn_start")
	assert_eq(spy.turn_starts, 1, "revoked effect must be unbucketed")


## The price of the has_method approach: a typo'd hook silently never fires.
## Every `_on_*` method on every Effect subclass must be a declared hook.
func test_every_declared_hook_name_is_legal() -> void:
	var legal := Effect.HOOKS.duplicate()
	legal.append_array(Effect.LIFECYCLE_HOOKS)
	var scanned := 0
	for entry in ProjectSettings.get_global_class_list():
		if not _extends_effect(entry):
			continue
		scanned += 1
		var script: Script = load(entry["path"])
		for m in script.get_script_method_list():
			var n := StringName(m["name"])
			if not String(n).begins_with("_on_"):
				continue
			assert_true(legal.has(n),
				"%s defines %s, which is not in Effect.HOOKS" % [entry["class"], n])
	# Guard the lint against passing vacuously: if the subclass walk ever stops
	# resolving, this test would silently stop checking anything.
	assert_gt(scanned, 0, "found no Effect subclasses to lint — the walk is broken")


func _extends_effect(entry: Dictionary) -> bool:
	var base: String = entry.get("base", "")
	var guard := 0
	while base != "" and guard < 16:
		if base == "Effect":
			return true
		var found := false
		for e in ProjectSettings.get_global_class_list():
			if e["class"] == base:
				base = e.get("base", "")
				found = true
				break
		if not found:
			return false
		guard += 1
	return false


# ── Grant ledger ────────────────────────────────────────────────────────────

func test_grant_duplicates_and_revoke_restores_baseline() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame
	var effect := StatEffect.new()
	var source := _mod(&"strength", 15.0)
	effect.modifiers = [source]

	var base: float = ent.stat_board.strength.value
	var inst := ent.grant_effect(effect)
	assert_eq(int(ent.stat_board.strength.value), int(base + 15))

	var handles := inst.handles_for(null)
	assert_eq(handles.size(), 1)
	assert_ne(handles[0], source, "grant must duplicate, never share the authored modifier")

	ent.revoke_effect(inst)
	assert_eq(int(ent.stat_board.strength.value), int(base))


func test_grant_to_node_target_lands_on_node_board_only() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var effect := InertEffect.new()
	var inst := ent.grant_effect(effect, node)
	var entity_armor: float = ent.stat_board.armor.value

	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = 5.0
	var handle := inst.context.grant(m, node)

	assert_eq(float(node.get_local_value(&"armor")), entity_armor + 5.0,
		"node-local grant must show up in the combined read")
	assert_eq(ent.stat_board.armor.value, entity_armor,
		"node-local grant must NOT touch the entity board")

	inst.context.revoke(handle)
	assert_eq(float(node.get_local_value(&"armor")), entity_armor)


func test_effect_can_grant_mid_life_from_a_hook() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var inst := ent.grant_effect(MidLifeEffect.new(), node)
	var base: float = float(node.get_local_value(&"armor"))
	assert_eq(inst.handles_for(node).size(), 0, "nothing granted at the boundary")

	ent.dispatch(&"_on_turn_start")
	assert_eq(inst.handles_for(node).size(), 1, "hook grant recorded in the ledger")
	assert_eq(float(node.get_local_value(&"armor")), base + 7.0)

	# Revoking the effect unwinds what the hook granted, not just _on_granted's work.
	ent.revoke_effect(inst)
	assert_eq(float(node.get_local_value(&"armor")), base)


func test_revoke_all_clears_every_target() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var inst := ent.grant_effect(InertEffect.new(), node)
	inst.context.grant(_mod(&"strength", 3.0))            # entity board
	inst.context.grant(_mod(&"armor", 4.0), node)         # node board
	assert_eq(inst.grants().size(), 2)

	inst.context.revoke_all()
	assert_eq(inst.grants().size(), 0)


# ── AllocationSystem wiring (the stub Keystone advertised for months) ────────

func _make_keystone(value: float) -> Keystone:
	var fx := StatEffect.new()
	fx.modifiers = [_mod(&"strength", value)]
	var ks := Keystone.new()
	ks.display_name = "K"
	ks.effects = [fx]
	return ks


func test_allocate_grants_node_effects_and_deallocate_revokes() -> void:
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	node.keystone = _make_keystone(20.0)
	var base: float = ent.stat_board.strength.value

	alloc.force_allocate(ent, node)
	assert_eq(int(ent.stat_board.strength.value), int(base + 20),
		"allocating a keystone node grants its effects")
	assert_eq(ent.get_effects().size(), 1)

	alloc.force_deallocate(node)
	assert_eq(int(ent.stat_board.strength.value), int(base),
		"deallocating revokes them")
	assert_eq(ent.get_effects().size(), 0)


## `_on_node_damaged` carries the POST-mitigation amount, so a defensive effect
## reacts to what actually landed rather than the attacker's claim.
func test_taking_damage_dispatches_node_damaged_post_mitigation() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent
	ent.core_location = node          # core: overflow routes to health, no depletion
	ent.stat_board.armor.base_value = 4.0
	ent.stat_board.min_damage_taken.base_value = 0.0

	var spy := DamageSpyEffect.new()
	ent.grant_effect(spy)
	node.take_damage(10.0, null)

	assert_eq(spy.hits.size(), 1)
	assert_almost_eq(spy.hits[0], 6.0, 0.001, "10 raw - 4 armor = 6 effective")


func test_allocation_dispatches_node_allocated_after_ownership_lands() -> void:
	var alloc := autofree(AllocationSystem.new()) as AllocationSystem
	var ent := _make_entity()
	var node := _make_node()
	add_child(alloc)
	add_child(ent)
	add_child(node)
	await get_tree().process_frame

	var spy := SpyEffect.new()
	ent.grant_effect(spy)
	alloc.force_allocate(ent, node)

	assert_eq(spy.allocations.size(), 1)
	assert_eq(spy.allocations[0], node)
	assert_eq(node.owned_by, ent, "ownership must already be committed when the hook fires")
