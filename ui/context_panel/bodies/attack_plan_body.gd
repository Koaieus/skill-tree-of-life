@tool
class_name AttackPlanBody
extends ContextBodyBase

## Context body for an active [AttackPlan]: dispatches on the plan's mode (melee
## / ranged / magic) and renders the relevant summary plus a live damage preview.
## Self-subscribes to [BattleSystem.attack_plan_changed] +
## [signal BattleSystem.attack_plan_state_changed] + selected_spell_changed so it
## re-renders on every plan mutation (pivot pick, blade extension, spell swap,
## target click) without the panel having to re-resolve. Salvaged from the old
## BattlePhaseBody (phase model removed in #60).

@onready var _mode_slot: VBoxContainer = $ModeSlot
@onready var _preview: Label = $DamagePreview

var _bound_system: BattleSystem = null


func _exit_tree() -> void:
	_disconnect_system()


func bind(p_entity: Entity, p_battle_system: BattleSystem,
		p_input_ctl: PlayerInputController, p_node: SkillNode = null) -> void:
	_disconnect_system()
	super(p_entity, p_battle_system, p_input_ctl, p_node)
	_bound_system = battle_system
	if _bound_system != null:
		_bound_system.attack_plan_changed.connect(_on_plan_changed)
		_bound_system.attack_plan_state_changed.connect(_render)
		_bound_system.selected_spell_changed.connect(_on_spell_changed)


func _disconnect_system() -> void:
	if _bound_system == null:
		return
	for sig in [&"attack_plan_changed", &"attack_plan_state_changed",
			&"selected_spell_changed"]:
		var cb: Callable
		match sig:
			&"attack_plan_changed": cb = _on_plan_changed
			&"attack_plan_state_changed": cb = _render
			&"selected_spell_changed": cb = _on_spell_changed
		if _bound_system.has_signal(sig) and _bound_system.is_connected(sig, cb):
			_bound_system.disconnect(sig, cb)
	_bound_system = null


func _on_plan_changed(_plan: AttackPlan) -> void:
	_render()


func _on_spell_changed(_spell: SpellDef) -> void:
	_render()


func rebuild() -> void:
	_render()


func _render() -> void:
	if not is_node_ready():
		return
	for child in _mode_slot.get_children():
		child.queue_free()
	_preview.text = ""
	var plan: AttackPlan = battle_system.attack_plan if battle_system != null else null
	if plan == null:
		_add_hint("Pick an attack mode below.")
		return
	if plan is MeleeAttackPlan:
		_render_melee(plan as MeleeAttackPlan)
	elif plan is RangedAttackPlan:
		_render_ranged(plan as RangedAttackPlan)
	elif plan is MagicAttackPlan:
		_render_magic(plan as MagicAttackPlan)
	_preview.text = _damage_preview_text(plan)


func _render_melee(plan: MeleeAttackPlan) -> void:
	var max_blade: int = 1
	if plan.attacker != null and plan.attacker.stat_board != null:
		var s := plan.attacker.stat_board.get_stat(&"blade_size")
		if s != null:
			max_blade = int(s.value)
	var selected: int = plan.blade_nodes.size()
	_add_value_row("Blade", "%d / %d" % [selected, max_blade])
	_add_hint("Right-click an owned node to pivot, left-click neighbours to extend.")


func _render_ranged(plan: RangedAttackPlan) -> void:
	var reaching: int = plan.get_reaching_firing_positions().size()
	var total_leaves: int = plan.get_firing_positions().size()
	_add_value_row("Firing", "%d / %d leaves" % [reaching, total_leaves])
	_add_hint("Each owned leaf whose range reaches the target adds one shot.")


func _render_magic(plan: MagicAttackPlan) -> void:
	var spell := plan.spell
	if spell == null:
		_add_hint("No spell equipped.")
		return
	var title := Label.new()
	title.text = "%s — %d mana" % [spell.name, spell.mana_cost]
	title.add_theme_font_size_override(&"font_size", 16)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_slot.add_child(title)
	_add_value_row("Min degree", str(spell.min_degree))
	if plan.source != null and plan.attacker != null and plan.attacker.navigator != null:
		_add_value_row("Source degree", str(plan.attacker.navigator.get_degree(plan.source)))
	if spell.description != "":
		var desc := Label.new()
		desc.text = spell.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mode_slot.add_child(desc)
	if spell.propagation != null:
		var prop_text := spell.propagation.get_description()
		if prop_text != "":
			var prop := Label.new()
			prop.text = prop_text
			prop.add_theme_color_override(&"font_color", Color(0.7, 0.85, 1.0))
			prop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_mode_slot.add_child(prop)


# --- Composition helpers --------------------------------------------------

func _add_hint(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = Color(1, 1, 1, 0.65)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_slot.add_child(lbl)


func _add_value_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.modulate = Color(1, 1, 1, 0.75)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	row.add_child(val)
	_mode_slot.add_child(row)


func _damage_preview_text(plan: AttackPlan) -> String:
	if not plan.is_valid():
		var errs := plan.validate()
		return "Plan incomplete: %s" % ", ".join(errs) if not errs.is_empty() else ""
	var outcome := plan.resolve()
	if outcome.hits.is_empty():
		return ""
	var total: float = 0.0
	for hit in outcome.hits:
		total += hit.amount
	var cost_parts: Array[String] = ["%d AP" % outcome.ap_cost]
	if outcome.mana_cost > 0:
		cost_parts.append("%d mana" % outcome.mana_cost)
	return "Preview: %s damage · %d hit%s · %s" % [
		_format_damage(total),
		outcome.hits.size(),
		"" if outcome.hits.size() == 1 else "s",
		", ".join(cost_parts),
	]


func _format_damage(d: float) -> String:
	return "%d" % roundi(d) if is_equal_approx(d, roundi(d)) else "%.1f" % d
