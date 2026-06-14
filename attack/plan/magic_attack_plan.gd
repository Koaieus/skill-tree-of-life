class_name MagicAttackPlan
extends AttackPlan

## Right-click an owned node to set the casting source; left-click a valid
## target per the equipped spell's targeting. Auto-equips a default spell at
## plan creation — spell-picker UI lands later.

const _DEFAULT_SPELL: SpellDef = preload("res://attack/spells/spark.tres")

var source: SkillNode = null
var spell: SpellDef = null
var target: SkillNode = null


func _init() -> void:
	mode = BattleSystem.AttackMode.MAGIC
	spell = _DEFAULT_SPELL


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


func get_highlight_role(node: SkillNode) -> HighlightRole:
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
	if target == null:
		errors.append(&'No target selected')
	return errors


func get_available_spells() -> Array[SpellDef]:
	return [spell] if spell != null else []


func _target_still_valid() -> bool:
	if spell == null or spell.targeting == null or source == null:
		return false
	return spell.targeting.is_valid_target(self, source, target)
