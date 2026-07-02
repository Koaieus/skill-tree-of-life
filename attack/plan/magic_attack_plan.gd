class_name MagicAttackPlan
extends AttackPlan

## Right-click an owned node to set the casting source; left-click a valid
## target per the equipped spell's targeting. The active spell comes from
## [BattleSystem.selected_spell] when the plan is constructed by the system;
## hand-instantiated plans (tests, AI scoring) can assign [member spell]
## directly. Falls back to the bundled default if nothing is selected so the
## plan is never silently unarmed.

const _FALLBACK_SPELL: SpellDef = preload("res://attack/spell/defs/spark.tres")

var source: SkillNode = null
var spell: SpellDef = null
var target: SkillNode = null


func _init() -> void:
	mode = BattleSystem.AttackMode.MAGIC
	spell = _FALLBACK_SPELL


func _on_node_right_clicked(node: SkillNode) -> void:
	if attacker == null or node == null or node.owned_by != attacker:
		return
	if node == source:
		source = null
	else:
		source = node
	if target != null and not _target_still_valid():
		target = null
	state_changed.emit()


func _on_node_left_clicked(node: SkillNode) -> void:
	if source == null or spell == null or spell.targeting == null:
		return
	if not spell.targeting.is_valid_target(self, source, node):
		return
	if target == node:
		return
	target = node
	state_changed.emit()


func reset() -> void:
	if source == null and target == null:
		return
	source = null
	target = null
	state_changed.emit()


func get_node_role(node: SkillNode) -> HighlightRole:
	if node == null:
		return HighlightRole.NONE
	if source != null and node == source:
		return HighlightRole.ORIGIN
	if target != null and node == target:
		return HighlightRole.HOSTILE_TARGET
	if source != null and spell != null and spell.targeting != null:
		if spell.targeting.is_valid_target(self, source, node):
			return HighlightRole.IN_RANGE
	return HighlightRole.NONE


func validate() -> Array[String]:
	var errors: Array[String] = []
	if spell == null:
		errors.append(&'No Spell selected')
	else:
		errors.append_array(spell.validate(self))
	if source == null:
		errors.append(&'No source selected')
	elif spell != null and attacker != null \
			and not _source_meets_min_degree(spell, source):
		errors.append(&'Source node degree too low for spell')
	if target == null:
		errors.append(&'No target selected')
	return errors


func _source_meets_min_degree(spell_def: SpellDef, src: SkillNode) -> bool:
	if attacker.spellbook != null:
		return attacker.spellbook.is_castable(spell_def, src, attacker)
	# No spellbook? Fall back to a direct navigator check — keeps the gate
	# functional for tests / scripted setups that skip the book entirely.
	if attacker.navigator == null:
		return false
	return attacker.navigator.get_degree(src) >= spell_def.min_degree


func get_available_spells() -> Array[SpellDef]:
	return [spell] if spell != null else []


func get_range_visual() -> RangeVisual:
	if source == null or spell == null or spell.targeting == null:
		return null
	var finder: RangeFinder = spell.targeting.range_finder
	if finder == null:
		return null
	return finder.get_visual(attacker, source)


func _target_still_valid() -> bool:
	if spell == null or spell.targeting == null or source == null:
		return false
	return spell.targeting.is_valid_target(self, source, target)


func resolve() -> AttackOutcome:
	if spell == null or source == null or target == null:
		return AttackOutcome.new()
	# Walk parents to find the Graph; SkillNodes live under Graph/SkillNodes.
	var n: Node = source
	while n != null and not (n is Graph):
		n = n.get_parent()
	var graph: Graph = n
	if graph == null:
		return AttackOutcome.new()
	var outcome := SpellResolver.resolve(spell, target, source, attacker, graph)
	outcome.mana_cost = spell.mana_cost
	return outcome


## Swap the equipped spell mid-plan. Clears the target if the new spell's
## targeting would reject it, so the player can't accidentally cast with a
## stale pick. Emits [signal state_changed] so the UI re-paints.
func set_spell(new_spell: SpellDef) -> void:
	if spell == new_spell:
		return
	spell = new_spell
	if target != null and not _target_still_valid():
		target = null
	state_changed.emit()
