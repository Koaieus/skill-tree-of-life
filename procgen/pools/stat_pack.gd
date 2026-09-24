@tool
class_name StatPack
extends Resource

## All procgen content belonging to one archetype (v4, #321). The unit of
## authoring — one `.tres` per archetype: strength.tres, dexterity.tres, …
## plus exactly one universal pack, `universal.tres` (`archetype_stat = &""`:
## armor, node_health, movement, deallocation).
##
## The pack is the ONLY archetype gate (#751): every pool in it rolls on a
## node iff [member archetype_stat] is `&""` or equals the node's
## `primary_stat` (and the pool's own `subtypes` admits the node's subtype) —
## see [method ModifierPoolSet.flatten_for_node]. Pools carry no archetype of
## their own, so a pool's scope is the file it sits in. `&""` is also the
## field's default, so "forgot to set it" reads as universal:
## `test_pool_scoping.gd` pins every pack's value to its file stem.
##
## Why pack content by archetype instead of by stat:
##  - Identity lives at the archetype level (a gold/WIS node IS a WIS-themed
##    node — its wisdom-stat AND xp_per_turn-stat content move together).
##  - Each [StatPool] inside `pools` still carries (stat_id, op), so
##    multi-stat archetypes like wisdom (wisdom + xp_per_turn) are first-class.
##
## #321 D7 removed the off-archetype phase entirely: there is no
## `off_phase_op_weights`, no `&"off"` phase, no `0.4` magic factor. All budget
## goes to the node's primary archetype; universal pools are the shared
## defensive/mobility content.

## The gate — matches against the node's `primary_stat`. `&""` = universal
## (`universal.tres` only).
@export var archetype_stat: StringName = &""

## All this pack's stat pools. Each [StatPool] describes its
## (stat_id, operation, tiers); the pack decides who draws them.
@export var pools: Array[StatPool] = []


func format_table() -> String:
	var lines: PackedStringArray = []
	var arch := String(archetype_stat) if archetype_stat != &"" else "—"
	lines.append("StatPack archetype=%s" % arch)
	for p in pools:
		if p == null:
			lines.append("  (null pool)")
			continue
		lines.append(p.format_table())
	return "\n".join(lines)


func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if pools.is_empty():
		out.append("no pools defined — pack contributes nothing.")
	for i in pools.size():
		var p: StatPool = pools[i]
		if p == null:
			out.append("pools[%d] is null." % i)
			continue
	return out
