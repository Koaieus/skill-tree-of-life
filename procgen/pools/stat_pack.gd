@tool
class_name StatPack
extends Resource

## All procgen content belonging to one archetype (v4, #321). The unit of
## authoring — one `.tres` per archetype: strength.tres, dexterity.tres, …
## plus the universal packs (`mobility.tres`, `constitution.tres`'s defensive
## half) with `archetype_stat = &""`.
##
## A pack MAY mix universal and archetype-affine pools: `constitution.tres`
## carries both CON-primary pools (`archetype_stat = &"constitution"`) and
## the universal defensive ones (node_health / armor, `archetype_stat = &""`).
## That is legal because [method ModifierPoolSet.flatten_for_node] filters on
## each [StatPool]'s own `archetype_stat` — the pack-level `archetype_stat`
## below is documentation, never a gate.
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

## Archetype affinity — matches against the node's `primary_stat`. Use `&""`
## for universal packs (defensive, mobility) that have no archetype identity.
@export var archetype_stat: StringName = &""

## Tags shared by this pack; auto-stamped onto every entry at flatten time so
## weight profiles can target archetype-wide. Validated against [TagRegistry].
@export var tags: Array[StringName] = []

## All this pack's stat pools. Each [StatPool] fully describes its
## (stat_id, operation, tiers) — the pack is just a grouping for authoring.
@export var pools: Array[StatPool] = []


func format_table() -> String:
	var lines: PackedStringArray = []
	var arch := String(archetype_stat) if archetype_stat != &"" else "—"
	lines.append("StatPack archetype=%s  tags=%s" % [arch, str(tags)])
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
		# Cross-check a pool's archetype_stat against the pack's, when it is
		# non-universal. Universal pools (empty archetype_stat) are legal in
		# any pack (constitution.tres's defensive half is the precedent).
		if p.archetype_stat != &"" and p.archetype_stat != archetype_stat:
			out.append("pools[%d] archetype_stat=%s != pack's %s (universal pools use &\"\")." % [
					i, String(p.archetype_stat), String(archetype_stat)])
	return out