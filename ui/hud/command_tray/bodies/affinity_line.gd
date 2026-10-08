@tool
class_name AffinityLine
extends HBoxContainer

## What one hit of the configured cast lands per concept — "Poison 9/hit ·
## Curse 2/hit": [method Infusion.affinity_of] for the plan's spell and
## infusion, folded through [method StatusDef.stacks_per_hit] on the caster's
## board — the numbers the landing itself uses. Hidden while the spell lands
## nothing.
##
## Binds to a bare [MagicAttackPlan] — the caster is [member AttackPlan.attacker]
## — and repaints on the plan's own [signal AttackPlan.state_changed], exactly as
## [InfusionRow] does, so a host only calls [method bind].

@onready var _value: Label = %Value

var _plan: MagicAttackPlan = null


func _ready() -> void:
	_refresh()


## Read [param plan]'s cast; null unbinds. Re-binding the bound plan is free.
func bind(plan: MagicAttackPlan) -> void:
	if plan == _plan:
		return
	if _plan != null and _plan.state_changed.is_connected(_refresh):
		_plan.state_changed.disconnect(_refresh)
	_plan = plan
	if _plan != null:
		_plan.state_changed.connect(_refresh)
	_refresh()


## The rendered line, "" while hidden.
func text() -> String:
	return _value.text if _value != null else ""


func _refresh() -> void:
	if not is_node_ready():
		return
	var parts := _parts()
	visible = not parts.is_empty()
	_value.text = " · ".join(parts)


func _parts() -> PackedStringArray:
	var parts: PackedStringArray = []
	if _plan == null or _plan.spell == null:
		return parts
	var spell := _plan.spell
	var board := _plan.attacker.stat_board if _plan.attacker != null else null
	var infusion := _plan.infusion if _plan.infusion != null else Infusion.innate(spell)
	var counts := infusion.affinity_of(spell)
	for id in counts:
		var status := _status_of(spell, id)
		if counts[id] <= 0 or status == null:
			continue
		var label := status.display_name if not status.display_name.is_empty() \
				else String(id)
		parts.append("%s %s/hit" % [label,
				NumFmt.num(status.stacks_per_hit(board, float(counts[id])))])
	return parts


## The status concept [param id] lands for [param spell]: its listed affinity's,
## else the concept's roster status — the lookup [method Infusion.riders] makes.
static func _status_of(spell: SpellDef, id: StringName) -> StatusDef:
	for affinity in spell.affinities:
		if affinity != null and affinity.status != null and affinity.aspect_id() == id:
			return affinity.status
	return StatusRoster.shared().by_concept(id)
