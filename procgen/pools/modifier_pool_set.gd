@tool
class_name ModifierPoolSet
extends Resource

## The procgen config's top-level modifier-content resource. Holds a flat list
## of [StatPack]s; the draw loop slices across them per phase. Replaces the
## single [ModifierPool] hanging off [GraphProcgenConfig] — `packs` here is
## the new authoring surface and [method flatten_for_phase] is what the draw
## loop calls.
##
## Composition between archetypes happens via the StringName link
## ([ArchetypePolicy.primary_stat] ↔ [StatPack.archetype_stat]). The set
## doesn't track "which pack is for which archetype" — the strings line up
## structurally.

@export var packs: Array[StatPack] = []

## Inspector button: dumps `format_tables()` to the editor output.
@export_tool_button("Print pools as tables") var _print_button: Callable = _print_tables

## Slot-count distribution per node. Keys = total modifier slots (int),
## values = sampling weights. Example: `{1: 5, 2: 55, 3: 30, 4: 8, 5: 2}`.
## Mean ~2.4 — combat backbone size, with long tail for sprawly nodes.
@export var slot_count_weights: Dictionary[int, float] = {1: 5.0, 2: 55.0, 3: 30.0, 4: 8.0, 5: 2.0}

## Primary share of slots (rest go to phase 3 / off-attribute / defensive / rare).
## `primary_share = ceil(slots * primary_share_ratio)`. At ratio 0.6:
## slots=1→1, 2→2, 3→2, 4→3, 5→3.
@export_range(0.0, 1.0) var primary_share_ratio: float = 0.6

## Off-attribute cost cap. Off-phase entries are filtered to
## `cost ≤ floor(peak_primary_cost * off_cost_cap_factor) - off_cost_cap_offset`.
## Note: this is a *cost* threshold, not a tier threshold — with geometric
## tier costs (1, 3, 9, 27, 81), offset=1 only excludes the exact-peak; for
## "off one full tier below primary" use factor≈0.4 instead.
## Defensive / rare pools are exempt from this cap.
@export var off_cost_cap_offset: int = 1
@export_range(0.0, 1.0) var off_cost_cap_factor: float = 1.0


func _print_tables() -> void:
	print(format_tables())


## Sample a total slot count from `slot_count_weights`. Defaults to 2 if the
## distribution is empty.
func sample_slot_count(rng: RandomNumberGenerator) -> int:
	if slot_count_weights.is_empty():
		return 2
	var total := 0.0
	for v in slot_count_weights.values():
		total += maxf(0.0, float(v))
	if total <= 0.0:
		return 2
	var r := rng.randf() * total
	for key in slot_count_weights.keys():
		var w := maxf(0.0, float(slot_count_weights[key]))
		r -= w
		if r <= 0.0:
			return maxi(1, int(key))
	return maxi(1, int(slot_count_weights.keys().back()))


## All entries flattened (debug / print-tool / one-shot consumers). The draw
## loop should prefer [method flatten_for_phase] which filters by role +
## archetype_stat in a single pass.
func flatten_all() -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	for pack in packs:
		if pack == null:
			continue
		for pool in pack.pools:
			if pool != null:
				out.append_array(pool.to_entries())
	return out


## Phase-aware flatten. Selects only the pools relevant to a given draw
## phase, then expands them. The off-phase branch additionally applies each
## source pack's [member StatPack.off_phase_op_weights] to entry weights
## (multiplying — zero hard-excludes).
##
##  phase = &"primary":   PRIMARY pools where archetype_stat == primary_stat
##  phase = &"off":       PRIMARY pools where archetype_stat != primary_stat
##                        (and != &""); off-attribute rolls, with pack-level
##                        suppression applied to entry weights
##  phase = &"defensive": DEFENSIVE pools (any pack)
##  phase = &"rare":      RARE pools (any pack)
func flatten_for_phase(
		phase: StringName,
		primary_stat: StringName,
) -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	for pack in packs:
		if pack == null:
			continue
		for pool in pack.pools:
			if pool == null:
				continue
			match phase:
				&"primary":
					if pool.role == TierPool.Role.PRIMARY and pool.archetype_stat == primary_stat:
						out.append_array(pool.to_entries())
				&"off":
					if (pool.role == TierPool.Role.PRIMARY
							and pool.archetype_stat != primary_stat
							and pool.archetype_stat != &""):
						# Apply pack-level suppression per operation. Zero
						# hard-excludes (we drop the entry rather than carry a
						# zero-weight ghost through the pipeline).
						var mult := pack.off_weight_for(pool.operation)
						if mult <= 0.0:
							continue
						for e in pool.to_entries():
							e.weight *= mult
							out.append(e)
				&"defensive":
					if pool.role == TierPool.Role.DEFENSIVE:
						out.append_array(pool.to_entries())
				&"rare":
					if pool.role == TierPool.Role.RARE:
						out.append_array(pool.to_entries())
	return out


## Markdown-ish dump of the whole set — what the print-tool emits.
func format_tables() -> String:
	var lines: PackedStringArray = []
	lines.append("ModifierPoolSet — %d packs" % packs.size())
	lines.append("  slot_count_weights=%s primary_share_ratio=%.2f off_cap=(factor=%.2f, offset=%d)" % [
			str(slot_count_weights), primary_share_ratio,
			off_cost_cap_factor, off_cost_cap_offset])
	for pack in packs:
		if pack == null:
			lines.append("(null pack)")
			continue
		lines.append("")
		lines.append(pack.format_table())
	return "\n".join(lines)
