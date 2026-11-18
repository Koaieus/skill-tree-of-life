@tool
class_name ConcentrateUse
extends LoadUse

## An Ice **shape** row's use (ADR 0084 §8): the load is a hop cut, 1 load per
## hop, priced at [member bonus_per_hop] on the cast's payload. [method spend]
## writes both on the [LoadBag] and adds no rider; [SpellResolver] reads them
## once, before wave 0 ([method LoadBag.hops_removed],
## [method LoadBag.multiplier]). A row running it is a *concentrate row*
## ([method Infusion.is_concentrate_row]), never planted. A variant cutting
## `max_visits` would be a second subclass.

## Payload bonus per hop removed: the cast's multiplier is
## `1 + bonus_per_hop × hops removed`. Tentative default, easy to change.
@export_range(0.0, 2.0, 0.05, "or_greater") var bonus_per_hop: float = 0.5:
	set(value):
		bonus_per_hop = maxf(value, 0.0)
		emit_changed()

static var _default: ConcentrateUse = null


## The shared use a spell with no authored concentrate row takes (1:1 is the
## absent row's affinity; [member bonus_per_hop] at its default). Shared: never
## mutate it.
static func shared_default() -> ConcentrateUse:
	if _default == null:
		_default = ConcentrateUse.new()
	return _default


func spend(_row: AspectIntake, _status: StatusDef, amount: int, bag: LoadBag) -> void:
	bag.hop_cut += maxi(amount, 0)
	bag.bonus_per_hop = bonus_per_hop


## The shape row's tooltip line: its price per hop and Ice per hop, or that the
## spell refuses an Ice shape (affinity 0).
func describe(row: AspectIntake, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	if row.refuses():
		return "Refuses an Ice shape."
	var per_hop := "1 Ice" if row.affinity_gain == row.affinity_cost \
			else "%s Ice" % NumFmt.num(float(row.affinity_cost) / row.affinity_gain)
	return "Ice shape: %s cuts 1 hop, +%d%% payload per hop cut." \
			% [per_hop, roundi(bonus_per_hop * 100.0)]
