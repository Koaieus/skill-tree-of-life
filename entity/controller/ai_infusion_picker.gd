class_name AiInfusionPicker
extends RefCounted

## The AI's infusion call: infusing costs nothing but slots, so every slot is
## filled to the cap and the only choice is which aspects. Aspects rank by
## `floor(aspect stat x spell rate)` descending, ties by [AspectRoster] order;
## each takes min(its own stat, what is left of the spell's
## `infusion_capacity`) — there is no shared points pool. Aspects the spell refuses
## (rate 0), the entity holds none of, or that land no status are skipped.


## `{concept id: points}` for [param spell] cast by [param entity]; empty when
## nothing can be spent.
static func pick(entity: Entity, spell: SpellDef) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if entity == null or spell == null or entity.stat_board == null:
		return out
	var slots := AspectCurrency.cap_of(entity, &"infusion_slots")
	var capped := not is_inf(spell.infusion_capacity)
	var left := maxi(0, floori(spell.infusion_capacity)) if capped else 0
	if slots <= 0 or (capped and left <= 0):
		return out
	var ranked: Array = []  # [id, held, ingest]
	for aspect in AspectRoster.shared().aspects:
		var id := aspect.id()
		var rate := Infusion.rate_of(spell, id)
		var held := AspectCurrency.cap_of(entity, AspectCurrency.stat_of(id))
		if rate <= 0.0 or held <= 0 or StatusRoster.shared().by_concept(id) == null:
			continue
		ranked.append([id, held, floori(held * rate)])
	# Stable by construction: roster order is the array order, ties keep it.
	var order: Array[int] = []
	for i in ranked.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ia: int = ranked[a][2]
		var ib: int = ranked[b][2]
		return ia > ib or (ia == ib and a < b))
	for i in order:
		if out.size() >= slots or (capped and left <= 0):
			break
		var spend: int = mini(ranked[i][1], left) if capped else ranked[i][1]
		out[ranked[i][0]] = spend
		left -= spend
	return out
