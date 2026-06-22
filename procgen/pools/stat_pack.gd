@tool
class_name StatPack
extends Resource

## All procgen content belonging to one archetype. The unit of authoring —
## one .tres per archetype: strength.tres, dexterity.tres, intelligence.tres,
## wisdom.tres, perception.tres, plus cross-cutting defensive.tres / rare.tres
## with `archetype_stat = &""`.
##
## Why pack content by archetype instead of by stat:
##  - Identity lives at the archetype level (a gold/WIS node IS a WIS-themed
##    node — its wisdom-stat AND xp_per_turn-stat content move together).
##  - Per-pack off-phase visibility knobs (see `off_phase_op_weights`) target
##    archetype-wide suppression (e.g. WIS is rare-everywhere), which would
##    duplicate across files if we sliced by stat.
##  - Each TierPool inside `pools` still carries (stat_id, op, role), so
##    multi-stat archetypes like wisdom (wisdom + xp_per_turn) are first-class.
##
## ModifierPoolSet aggregates StatPacks and runs the phased draw across all of
## them — composition between archetypes happens via the StringName link
## (ArchetypePolicy.primary_stat ↔ StatPack.archetype_stat).

## Archetype affinity — matches against the node's `primary_stat` meta. Use
## &"" for cross-cutting packs (defensive, rare) that have no archetype
## identity.
@export var archetype_stat: StringName = &""

## Tags shared by this pack; auto-stamped onto every entry at flatten time so
## weight profiles can target archetype-wide. Validated against [TagRegistry].
@export var tags: Array[StringName] = []

## All this pack's tier pools. Each pool fully describes its (stat_id,
## operation, role, tiers) — the pack is just a grouping for authoring +
## off-phase suppression.
@export var pools: Array[TierPool] = []

## Off-phase visibility knob. When this pack's `archetype_stat` !=
## `node.primary_stat` and an entry from this pack is considered in phase 3,
## its sampling weight is multiplied by `off_phase_op_weights[entry.operation]`.
## Use 0.0 for hard-exclude (e.g. WIS "never MULTIPLY off-primary").
##
## Default of empty dict acts as all-1.0 (no suppression beyond cost cap).
## Only set for archetypes that should fade out outside their home.
@export var off_phase_op_weights: Dictionary[StatModifier.Operation, float] = {}


## Returns the off-phase weight multiplier for a given operation. Missing keys
## default to 1.0 (no suppression).
func off_weight_for(op: StatModifier.Operation) -> float:
	return float(off_phase_op_weights.get(op, 1.0))


func format_table() -> String:
	var lines: PackedStringArray = []
	var arch := String(archetype_stat) if archetype_stat != &"" else "—"
	lines.append("StatPack archetype=%s  tags=%s" % [arch, str(tags)])
	if not off_phase_op_weights.is_empty():
		var parts: PackedStringArray = []
		for op in off_phase_op_weights.keys():
			parts.append("%s:%.2f" % [_op_short(op), float(off_phase_op_weights[op])])
		lines.append("  off_phase_op_weights: %s" % ", ".join(parts))
	for p in pools:
		if p == null:
			lines.append("  (null pool)")
			continue
		lines.append(p.format_table())
	return "\n".join(lines)


static func _op_short(op: StatModifier.Operation) -> String:
	match op:
		StatModifier.Operation.ADD_BASE: return "addb"
		StatModifier.Operation.INCREASE: return "inc"
		StatModifier.Operation.MULTIPLY: return "mul"
		StatModifier.Operation.ADD_BONUS: return "addn"
		StatModifier.Operation.SET: return "set"
	return "op"


func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if pools.is_empty():
		out.append("no pools defined — pack contributes nothing.")
	for i in pools.size():
		var p: TierPool = pools[i]
		if p == null:
			out.append("pools[%d] is null." % i)
			continue
		# Cross-check pool's archetype_stat against the pack's (PRIMARY pools only).
		if p.role == TierPool.Role.PRIMARY and p.archetype_stat != archetype_stat:
			out.append("pools[%d] PRIMARY but archetype_stat=%s != pack's %s" % [
					i, String(p.archetype_stat), String(archetype_stat)])
	return out
