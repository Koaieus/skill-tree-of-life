@tool
class_name CombatCardMagic
extends CombatReadoutCard
## Magic readout: selected spell's potency/instance + hop reach ("rare" tag
## when [member PropagationConfig.max_hops] is nonzero). Bound to whichever
## spell [member ArmedStack.selected_spell] currently points at — null-safe.
##
## The Reach row has two tiers. No spell selected: the row DESCRIBES the
## caster's `cast_range_hops` pipeline as text ("(X+3) × 1.5") via
## [method Stat.resolve_with] — the card never assembles bins itself, the
## fold belongs to the stat. Spell selected: the number
## [method SpellRangeRules.reach] answers for the authored `max_hops`, never
## the raw authored value.
##
## Potency is the [b]computed seed[/b] — [code]spell_damage × power[/code] for
## the bound caster — not the raw [member SpellDef.power] coefficient, which is
## meaningless on its own (D-32). It therefore moves when INT does, which is
## why the card also listens to the stat.
##
## The Affinity row is what one hit lands per concept for the armed plan's
## infusion: [method Infusion.affinity_of] folded through
## [method StatusDef.stacks_per_hit] — the numbers the landing itself uses. With
## no magic plan it reads the spell's innate affinities. It is instanced here
## (not authored in the card scene) and hides when the spell lands nothing.

const _VALUE_ROW_SCENE := preload("res://ui/hud/combat_readout/combat_value_row.tscn")

@onready var _potency_row: CombatValueRow = %PotencyRow
@onready var _reach_row: CombatValueRow = %ReachRow

var _armed_stack: ArmedStack
var _affinity_row: CombatValueRow

var _spell: SpellDef:
	get = _get_spell, set = _set_spell 


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	if board.spell_damage != null:
		_binds.link(board.spell_damage.value_changed, _refresh)
	var reach: Stat = board.get_stat(&"cast_range_hops")
	if reach != null:
		_binds.link(reach.value_changed, _refresh)
	if _armed_stack != null:
		_binds.link(_armed_stack.selected_spell_changed, _set_spell)

func _ready() -> void:
	super._ready()
	_affinity_row = _VALUE_ROW_SCENE.instantiate() as CombatValueRow
	_affinity_row.name = "AffinityRow"
	_affinity_row.row_label = "Affinity"
	_affinity_row.visible = false
	_potency_row.get_parent().add_child(_affinity_row)


func _get_spell() -> SpellDef:
	if _spell != null:
		return _spell
	return _armed_stack.selected_spell if _armed_stack else null
	
func _set_spell(spell: SpellDef = null):
	if spell != null and spell == _spell: return
	_spell = spell
	_refresh()

func _refresh() -> void:
	super._refresh()
	var spell := _spell
	_potency_row.set_value(SpellResolver.impact_damage(spell, null, _board))
	_refresh_affinity()
	if spell == null:
		var reach: Stat = _board.get_stat(&"cast_range_hops") if _board != null else null
		if reach != null:
			_reach_row.set_text(reach.resolve_with([]).describe())
		else:
			_reach_row.set_value(0.0)
		_reach_row.set_sliver("")
		return
	var authored: float = spell.propagation.max_hops if spell.propagation != null else 0.0
	if is_inf(authored):
		_reach_row.set_text("∞ hops")
	else:
		var hops := SpellRangeRules.reach(&"cast_range_hops", authored, _owner_entity,
				_hover_node, _board)
		_reach_row.set_value(hops, " hops")
	_reach_row.set_sliver("rare" if authored > 0 else "")


## "Poison 9/hit · Curse 2/hit" for the plan's spell and infusion (else the
## selected spell, innate); empty hides the row.
func _refresh_affinity() -> void:
	if _affinity_row == null:
		return
	var magic := _plan as MagicAttackPlan
	var spell := magic.spell if magic != null and magic.spell != null else _spell
	var parts: PackedStringArray = []
	if spell != null:
		var infusion := magic.infusion if magic != null and magic.spell == spell \
				else Infusion.innate(spell)
		var counts := infusion.affinity_of(spell)
		for id in counts:
			var status := _status_of(spell, id)
			if counts[id] <= 0 or status == null:
				continue
			var label := status.display_name if not status.display_name.is_empty() \
					else String(id)
			parts.append("%s %s/hit" % [label,
					NumFmt.num(status.stacks_per_hit(_board, float(counts[id])))])
	_affinity_row.visible = not parts.is_empty()
	_affinity_row.set_text(" · ".join(parts))


## The status concept [param id] lands for [param spell]: its listed affinity's,
## else the concept's roster status — the lookup [method Infusion.riders] makes.
static func _status_of(spell: SpellDef, id: StringName) -> StatusDef:
	for affinity in spell.affinities:
		if affinity != null and affinity.status != null and affinity.aspect_id() == id:
			return affinity.status
	return StatusRoster.shared().by_concept(id)
