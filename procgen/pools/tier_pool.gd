@tool
class_name TierPool
extends Resource

## Authoring unit for procgen modifier content. One TierPool .tres ≈ one
## (stat, op, archetype_affinity, role) tuple plus an ordered list of tiers.
## Replaces the flat-list [ModifierPool] authoring shape — same draw mechanics
## downstream, but you no longer maintain 50+ near-duplicate entries by hand.
##
## Mapping to runtime: each [TierDef] in `tiers` becomes one
## [ModifierPoolEntry] via [method to_entries], expanded once when
## [ModifierPoolSet] is built. Weight profiles, collision detection, the draw
## loop — all keep working on entries; TierPool is just the author surface.
##
## Archetype affinity vs target stat:
##   - `stat_id` is what the modifier writes to (e.g. `&"xp_per_turn"`).
##   - `archetype_stat` is which archetype's nodes the pool belongs to
##     (e.g. `&"wisdom"`). The phased draw matches `archetype_stat` against
##     the node's `primary_stat` meta. Leave empty when the pool is universal
##     or rare (no archetype affinity).
##
## Roles:
##   - PRIMARY: stat-coherent. Phase 2 picks from pools matching the node's
##     primary_stat; phase 3 picks off-attribute (other archetype_stat values),
##     cost-capped relative to the primary phase's peak.
##   - DEFENSIVE: always-available defensive content (node_health, armor).
##     Phase 3 picks without the off-attribute cost cap.
##   - RARE: low-weight, high-cost exotic content (-1 min_damage_taken,
##     +50 flat vision_range). Radial-gated to outer regions via weight profile.

enum Role { PRIMARY, DEFENSIVE, RARE }

## Target stat the rolled modifier writes to.
@export var stat_id: StringName = &""
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_BASE

## Archetype affinity — the node's `primary_stat` value this pool belongs to.
## Empty for DEFENSIVE / RARE pools (no archetype identity).
@export var archetype_stat: StringName = &""

@export var role: Role = Role.PRIMARY

## Tags shared by every tier in this pool. Validated against [TagRegistry].
@export var tags: Array[StringName] = []

## Tiers ordered T1..Tn ascending (convention only — the draw loop sorts on
## cost/weight, not tier index).
@export var tiers: Array[TierDef] = []


## Flatten this pool into runtime entries. Stable id generated per tier as
## `<stat_id>_<op>_<archetype_stat>_t<tier>` so weight profiles can target
## stably across re-flattens.
func to_entries() -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	var op_short := _op_short()
	var arch_seg := String(archetype_stat) if archetype_stat != &"" else "any"
	for t in tiers:
		if t == null:
			continue
		var e := ModifierPoolEntry.new()
		e.id = StringName("%s_%s_%s_t%d" % [stat_id, op_short, arch_seg, t.tier])
		e.stat_id = stat_id
		e.operation = operation
		e.value_range = t.value_range
		e.cost = t.cost
		e.weight = t.weight
		var merged: Array[StringName] = []
		merged.append_array(tags)
		merged.append_array(t.extra_tags)
		e.tags = merged
		out.append(e)
	return out


func _op_short() -> String:
	match operation:
		StatModifier.Operation.ADD_BASE: return "addb"
		StatModifier.Operation.INCREASE: return "inc"
		StatModifier.Operation.MULTIPLY: return "mul"
		StatModifier.Operation.ADD_BONUS: return "addn"
		StatModifier.Operation.SET: return "set"
	return "op"


## Markdown-ish table of this pool for the print-tool. Caller prefixes with
## the pool's identifying name.
func format_table() -> String:
	var lines: PackedStringArray = []
	var role_str: String = ["PRIMARY", "DEFENSIVE", "RARE"][int(role)]
	var arch := String(archetype_stat) if archetype_stat != &"" else "—"
	lines.append("  stat=%s op=%s role=%s archetype=%s tags=%s" % [
			String(stat_id), _op_short(), role_str, arch, str(tags)])
	lines.append("  tier  value_range          cost  weight  extra_tags")
	lines.append("  ----  -------------------  ----  ------  ----------")
	var total_weight := 0.0
	for t in tiers:
		if t != null:
			total_weight += maxf(0.0, t.weight)
	for t in tiers:
		if t == null:
			lines.append("  (null tier)")
			continue
		var pct := (100.0 * t.weight / total_weight) if total_weight > 0.0 else 0.0
		lines.append("  T%-3d  [%6.2f, %6.2f]    %-4d  %5.2f (%4.1f%%)  %s" % [
				t.tier, t.value_range.x, t.value_range.y, t.cost, t.weight, pct,
				str(t.extra_tags)])
	return "\n".join(lines)


func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if stat_id == &"":
		out.append("stat_id is empty — entries will mint StatModifiers targeting nothing.")
	if role == Role.PRIMARY and archetype_stat == &"":
		out.append("PRIMARY-role pool has no archetype_stat — phase 2 will never pick from it.")
	if tiers.is_empty():
		out.append("no tiers defined — pool will draw nothing.")
	for i in tiers.size():
		var t: TierDef = tiers[i]
		if t == null:
			out.append("tier[%d] is null." % i)
			continue
		if t.cost < 1:
			out.append("tier[%d] cost < 1 — breaks per-node draw cap." % i)
		if t.value_range.x > t.value_range.y:
			out.append("tier[%d] value_range inverted (%.2f > %.2f)." % [i, t.value_range.x, t.value_range.y])
	var registry := TagRegistry.canonical()
	if registry != null:
		var unknown := registry.unknown_tags(tags)
		for tag in unknown:
			out.append("unknown tag: %s" % String(tag))
	return out
