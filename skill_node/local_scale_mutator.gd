class_name LocalScaleMutator
extends RefCounted

## The local-scale mutator (#376): a STATELESS verb over a [NodeState] and the
## boards its modifiers contribute to. It reads [member NodeState.modifiers],
## [member NodeState.local_modifiers] and the effects it is handed, writes
## canonical [member StatModifier.value]s in place (share-safe via
## `Resource.changed`) and the two composition ledgers on the state. The
## [SkillNode] owns the trigger (its stake pool's `current_changed`), the state
## owns the ledgers, this class owns the law (docs/adr/0004).
##
## [param source] on the effect path is the [SkillNode] the effects were
## granted from — the key [Entity] files effect instances under. A bare state
## (no node) passes no effects and never reaches it.

# ── Local-scale mutator (#376) ───────────────────────────────────────────────
#
# The magnitude curve: every node-local and node-granted-to-entity modifier
# scales with the allocation level, per a per-operation law. SkillNode is the
# AUTHORITY over the canonical instances; the entity board (and node_board)
# hold references to the same instances, so a live `value` write propagates
# with no re-grant. The ladder is linear by default; `_local_scale` is the
# one line to swap for a curve.
#
# The mutator only ever writes `m.value` (share-safe via Resource.changed) —
# it never touches `_board` / `_bound_sources` / `_propagating` (decision 9).
# Composition mutations (Array overrides) are the one stateful exception: the
# swap ledger tracks which scaled leaf-set is currently applied in a parent's
# place, so the restore is exact.

## The ladder: al → scale factor. Identity, floored at 1 so an unowned node
## (al 0) reads as the baseline — going 0→1 is a ×1 no-op and 1→0 restores
## the authored value exactly. Swap the body for a curve later = one line.
func _local_scale(al: int) -> float:
	return maxf(float(al), 1.0)


func _laddered_multiply(value: float, old_al: int, new_al: int) -> float:
	# "Add the growth part": X(al) = 1 + (X_base - 1) × ladder(al), so the
	# transition is X_new = 1 + (X_old - 1) × ladder(new) / ladder(old) —
	# the exact inverse of the up-scale, so round-trips don't drift.
	return 1.0 + (value - 1.0) * _local_scale(new_al) / _local_scale(old_al)


## Run one mutator pass for a fill transition. Walks the node's entity-scoped
## modifiers, its node-local ledger (which includes addons), and its effects
## (composition path only — see [method _scale_effect]). Iterates UNTYPED
## copies: an `is CompositeStatModifier` on a typed-array loop variable is a
## parse error in this repo (.claude/rules/stats-system.md).
func apply(state: NodeState, old_al: int, new_al: int, effects: Array[Effect] = [], source: SkillNode = null) -> void:
	if old_al == new_al:
		return
	var entity_mods: Array = state.modifiers
	for m in entity_mods:
		scale_modifier(state, m, old_al, new_al)
	var local_mods: Array = state.local_modifiers
	for m in local_mods:
		scale_modifier(state, m, old_al, new_al)
	for e in effects:
		_scale_effect(state, e, old_al, new_al, source)


func scale_modifier(state: NodeState, m: StatModifier, old_al: int, new_al: int) -> void:
	if m == null:
		return
	if m.scales_with(&"stake_level"):
		return  # already al-scaled by formula — the #375 parallel path
	var override: Variant = m._local_scale_override(old_al, new_al)
	# Type-guard the sentinel BEFORE comparing: a Variant holding an Array or
	# float cannot be ==-compared with a StringName (runtime error, not false).
	if override is StringName and override == StatModifier.UNSCALED:
		return
	if override is float or override is int:
		_restore_scaled_contribution(state, m)
		m.value = float(override)
		return
	if override is Array:
		_swap_scaled_contribution(state, m, override)
		return
	if override != null:
		push_warning("LocalScaleMutator.apply: modifier '%s' returned unsupported override type %s; falling through to the universal law" % [m.resource_path, typeof(override)])
	# Universal law (null override).
	_restore_scaled_contribution(state, m)
	if m is CompositeStatModifier:
		for leaf in m.flatten():
			scale_modifier(state, leaf, old_al, new_al)
		return
	match m.operation:
		StatModifier.Operation.ADD_BASE, StatModifier.Operation.ADD_BONUS, StatModifier.Operation.INCREASE:
			# "+X → +X × ladder(al)" — value × ladder(new)/ladder(old) is
			# exact for integer ladders (5 × 2/1 = 10, 10 × 1/2 = 5).
			m.value = m.value * _local_scale(new_al) / _local_scale(old_al)
		StatModifier.Operation.MULTIPLY:
			m.value = _laddered_multiply(m.value, old_al, new_al)
		StatModifier.Operation.SET:
			pass  # SET opts out of the universal law by default (#376 decision 7)


## The board a modifier is applied to: the entity board for entity-scoped
## modifiers (when owned), node_board for the local ledger. null when the
## modifier is not currently applied anywhere (unowned entity grants).
func _contribution_board(state: NodeState, m: StatModifier) -> StatBoard:
	if state.owned_by != null and state.owned_by.stat_board != null and state.modifiers.has(m):
		return state.owned_by.stat_board
	if state.board_ready and state.local_modifiers.has(m):
		return state.board
	return null


## Composition mutation (decision 8): replace the parent's applied contribution
## with the override's scaled leaf-set. The parent STAYS in its ledger (it is
## still the canonical authority); `state.scaled_sets` tracks what the board
## actually holds so the restore is exact.
func _swap_scaled_contribution(state: NodeState, m: StatModifier, leaves: Array) -> void:
	var board := _contribution_board(state, m)
	if board == null:
		return  # unowned / not applied: nothing to swap on the board
	var prev: Array = state.scaled_sets.get(m, [])
	if not prev.is_empty():
		_remove_leaf_set(state, board, prev)
	else:
		board.remove_modifier(m)
	_apply_leaf_set(state, board, leaves)
	state.scaled_sets[m] = leaves


## Reverse of [method _swap_scaled_contribution]: put the parent's own leaves
## back where the scaled set was.
func _restore_scaled_contribution(state: NodeState, m: StatModifier) -> void:
	var prev: Array = state.scaled_sets.get(m, [])
	if prev.is_empty():
		return
	var board := _contribution_board(state, m)
	state.scaled_sets.erase(m)
	if board == null:
		return  # the board is gone (dealloc); nothing to restore on it
	_remove_leaf_set(state, board, prev)
	_apply_leaf_set(state, board, m.flatten())


## Node boards are sparse — a scaled set may target stats the board doesn't
## carry yet, so the local apply/remove paths ensure (apply) or no-op
## (remove) through the stat lookup, mirroring add/remove_local_modifier.
func _apply_leaf_set(state: NodeState, board: StatBoard, leaves: Array) -> void:
	for leaf in leaves:
		if state.board_ready and board == state.board:
			state.board.bind_modifier(leaf)
			state.board._ensure_stat(leaf.stat_id).add_modifier(leaf, state.board)
		else:
			board.add_modifier(leaf)


func _remove_leaf_set(state: NodeState, board: StatBoard, leaves: Array) -> void:
	for leaf in leaves:
		if state.board_ready and board == state.board:
			state.board.unbind_modifier(leaf)
			var s: Stat = state.board.get_stat(leaf.stat_id)
			if s != null:
				s.remove_modifier(leaf, state.board)
		else:
			board.remove_modifier(leaf)


## Effect composition path (acceptance 6): an effect whose override returns an
## Array has its granted contribution replaced on the entity board with the
## scaled leaf-set. Effects never value-scale — their canonical modifiers are
## shared .tres instances, so a Float override is rejected with a warning.
func _scale_effect(state: NodeState, e: Effect, old_al: int, new_al: int, source: SkillNode) -> void:
	if e == null:
		return
	var override: Variant = e._local_scale_override(old_al, new_al)
	if override is StringName and override == StatModifier.UNSCALED:
		return
	if override is Array:
		var entity := state.owned_by
		if entity == null or entity.stat_board == null:
			return
		if state.scaled_effect_sets.has(e):
			_remove_leaf_set(state, entity.stat_board, state.scaled_effect_sets[e])
			state.scaled_effect_sets.erase(e)
		else:
			for inst in entity.get_effects():
				if inst.source_node == source and inst.effect == e:
					entity.revoke_effect(inst)
		_apply_leaf_set(state, entity.stat_board, override)
		state.scaled_effect_sets[e] = override
		return
	# Identity form: restore a previously-swapped contribution, then stop.
	if state.scaled_effect_sets.has(e):
		_restore_scaled_effect(state, e, source)
	if override == null:
		return
	if override is float or override is int:
		push_warning("LocalScaleMutator._scale_effect: effect '%s' returned a Float override — effects carry shared .tres modifiers; use the Array (composition) form" % e.resource_path)
		return
	push_warning("LocalScaleMutator._scale_effect: effect '%s' returned unsupported override type %s" % [e.resource_path, typeof(override)])


func _restore_scaled_effect(state: NodeState, e: Effect, source: SkillNode) -> void:
	var entity := state.owned_by
	if entity == null or entity.stat_board == null:
		state.scaled_effect_sets.erase(e)
		return
	_remove_leaf_set(state, entity.stat_board, state.scaled_effect_sets[e])
	state.scaled_effect_sets.erase(e)
	entity.grant_effect(e, source)


## Every leaf currently applied through a scaled effect-set — the read half of
## [method clear_scaled_effect_sets] (#520), for the same reason
## [method granted_entity_modifiers] exists.
func scaled_effect_leaves(state: NodeState) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for e in state.scaled_effect_sets:
		for leaf: StatModifier in state.scaled_effect_sets[e]:
			out.append(leaf)
	return out


## Strip any scaled effect-sets applied to [param board] — called by
## AllocationSystem just before an ownership transition revokes the effect
## instances, because a swapped set is applied OUTSIDE the effect ledger and
## would strand on the board otherwise.
##
## Note this one was ALREADY shadow-safe: it only ever removed leaves from the
## board it was handed and never touched [member state.scaled_effect_sets] (#520's
## body reads it as mutating the node; it does not). Kept as the named verb, now
## expressed over [method scaled_effect_leaves] so there is one answer to "what
## did the swap put on the board".
func clear_scaled_effect_sets(state: NodeState, board: StatBoard) -> void:
	if board == null:
		return
	_remove_leaf_set(state, board, scaled_effect_leaves(state))
	state.scaled_effect_sets.clear()
