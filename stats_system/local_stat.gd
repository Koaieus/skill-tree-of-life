@tool
class_name LocalStat
extends Stat

## A Stat scoped to one SkillNode. Owns its own modifiers (and thus its own
## bins inherited from Stat), but composes them with an entity-side Stat on
## read so PoE pipeline semantics stay correct across both scopes.
##
## The trick is **bin-sum + one pipeline run**, not chained pipelines.
## Chaining (entity result → local base) double-applies INCREASEs against
## MULTIPLYs; ModifierBins.compute([entity.bins, self.bins], entity.base_value)
## doesn't. See modifier_bins.gd for the algebra.
##
## SET tiebreak: **local wins** at equal priority — addon intent is the more
## specific override. The sources order [entity.bins, self.bins] makes this
## fall out of ModifierBins._pick_set_winner's "last source wins on equal
## priority" rule for free.
##
## Entity-side absent (entity_stat == null)? Falls through to plain Stat
## behavior — no special case, the local stat just acts standalone.

var entity_stat: Stat = null:
	set(v):
		if entity_stat == v:
			return
		if entity_stat != null and entity_stat.value_changed.is_connected(_on_entity_changed):
			entity_stat.value_changed.disconnect(_on_entity_changed)
		entity_stat = v
		if entity_stat != null:
			entity_stat.value_changed.connect(_on_entity_changed)
		value_changed.emit()


func get_value() -> Variant:
	if entity_stat == null:
		return super.get_value()
	var sources: Array[ModifierBins] = [entity_stat.bins, bins]
	return _coerce(ModifierBins.compute(entity_stat.base_value, sources))


func _on_entity_changed() -> void:
	value_changed.emit()
