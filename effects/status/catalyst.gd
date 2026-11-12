@tool
class_name CatalystStatus
extends StatusDef

## Catalyst (#1801; `docs/design/elements/terrain.md` § The threshold model): an
## element-generic converter that sits on a node. The Heat, Cold or Charge
## stacks that land on its node take the whole store with them, split pro rata
## over the landing elements ([method converted]); a node crossing T into
## Burning, Frozen or Shocked takes the whole store left into that element,
## read at settle ([TerrainSettle.PrimeConversion]). Flow at or below T never
## converts. The row caps at its node's k × T ([member cap_k_times_t]).
##
## [method converted] is the pure split, in Catalyst stacks. [method convert] is
## the one door that takes a node's row: it splits, trades each part at
## [member ratio_in] : [member ratio_out], takes what it spent off the row and
## hands back the stacks to land. The land step (#1798's gather) and the settle
## seat both call [method convert], never [method converted] plus a ratio of
## their own.

## The trade rate: [member ratio_in] Catalyst for [member ratio_out] stacks of
## the landing element; a part converts to `part × ratio_out / ratio_in`
## (integer division). Tentative, easy to change; editor feedback: the status
## sandbox tab.
@export_range(1, 10, 1, "or_greater") var ratio_in: int = 1
@export_range(1, 10, 1, "or_greater") var ratio_out: int = 1
## Caps the row at its node's k × T ([method NodeCombat.terrain_cap], #1794).
## Off: [member StatusDef.power_max] alone. Tentative.
@export var cap_k_times_t: bool = true


## The split of [param store] Catalyst over [param landing] (element id →
## stacks landing; entries <= 0 ignored), pro rata, in Catalyst stacks before
## the trade, so the store's leftover is [param store] minus their sum. Each
## element's share `store × w / W` is floored; the stacks left go one per
## element down the remainders, largest first, a whole tied group at a time,
## and a group the leftover cannot cover (a stack that would have to pick
## between tied remainders) stays Catalyst. Integer only, roll-free. Returns
## element id → part, parts > 0 only, in [param landing]'s order. It takes no
## primary element: only the landing stacks count.
static func converted(store: int, landing: Dictionary) -> Dictionary:
	var out := {}
	var weights := {}
	var total := 0
	for e: Variant in landing:
		var w := int(landing[e])
		if w > 0:
			weights[e] = w
			total += w
	if store <= 0 or total <= 0:
		return out
	var parts := {}
	var rems := {}
	var left := store
	for e: Variant in weights:
		var share: int = store * int(weights[e])
		@warning_ignore("integer_division")
		var part: int = share / total
		parts[e] = part
		rems[e] = share % total
		left -= part
	while left > 0:
		var top := 0
		for e: Variant in rems:
			top = maxi(top, int(rems[e]))
		if top <= 0:
			break
		var group: Array = []
		for e: Variant in rems:
			if int(rems[e]) == top:
				group.append(e)
		if group.size() > left:
			break
		for e: Variant in group:
			parts[e] = int(parts[e]) + 1
			rems.erase(e)
		left -= group.size()
	for e: Variant in parts:
		if int(parts[e]) > 0:
			out[e] = parts[e]
	return out


## The stacks a [param part] of Catalyst trades into: `part × ratio_out /
## ratio_in`, integer division.
func traded(part: int) -> int:
	@warning_ignore("integer_division")
	return part * ratio_out / maxi(ratio_in, 1)


## The Catalyst a [param part] spends on its [method traded] stacks: the least
## that buys them, so the rest of the part stays Catalyst. The whole part while
## [member ratio_in] is 1; past it the remainder's law is tentative (the spec
## leaves it open).
func spent(part: int) -> int:
	var made := traded(part)
	@warning_ignore("integer_division")
	return mini(part, (made * maxi(ratio_in, 1) + ratio_out - 1) / maxi(ratio_out, 1))


## Convert [param host]'s row (the def's one row: Catalyst has no `group_by`)
## over [param landing], element id → stacks landing: split ([method
## converted]), trade each part ([method traded]), take the spent Catalyst off
## the row, and return element id → stacks to land on top of [param landing]'s
## own. The caller passes only terrain elements (Heat, Cold, Charge) and writes
## the result; this writes the row only. Empty when the row is empty or nothing
## lands.
func convert(host, landing: Dictionary) -> Dictionary:
	var out := {}
	if host == null:
		return out
	var parts := converted(int(host.get_status_power(id)), landing)
	var spend := 0
	for e: Variant in parts:
		var made := traded(int(parts[e]))
		if made > 0:
			out[e] = made
			spend += spent(int(parts[e]))
	if spend > 0:
		host.adjust_status_power(self, -float(spend))
	return out


## The row's cap on [param host]: its k × T while [member cap_k_times_t] and the
## host is a node that has one; 0 (none of its own) otherwise.
func cap_on(host) -> int:
	if not cap_k_times_t or host == null or not host.has_method(&"terrain_cap"):
		return 0
	return int(host.terrain_cap())


## Trims the raw row back to [method cap_on] when a landing or a move took it
## past. The status host clamps at [member StatusDef.power_max] only; a per-host
## cap there would replace this hook. Re-enters once: the trim lands at the cap.
func _on_applied(host, _power: float) -> void:
	var cap := cap_on(host)
	if cap <= 0:
		return
	var raw := int(host.get_status_power(id))
	if raw > cap:
		host.adjust_status_power(self, float(cap - raw))
