@tool
class_name ModifierPoolSet
extends Resource

## The procgen config's top-level modifier-content resource (v4, #321). Holds
## a flat list of [StatPack]s; the draw loop flattens the relevant pools per
## node and spends budget until broke. Slots, the off-archetype phase, and the
## primary/off share split are **deleted** (#321 D3, D7) — the draw is now
## spend-until-broke with per-(stat,op) aggregation, and all budget goes to
## the node's primary archetype (universal `archetype_stat == &""` pools stay
## shared as the defensive/mobility content).
##
## See [method GraphProcgen._roll_modifiers_v4] and docs/domain/procgen-v4.md.

@export var packs: Array[StatPack] = []

@export_range(0.0, 1.0) var universal_share: float = 0.2

## Inspector button: dumps `format_tables()` to the editor output.
@export_tool_button("Print pools as tables") var _print_button: Callable = _print_tables


func _print_tables() -> void:
	print(format_tables())


## All entries flattened (debug / print-tool / one-shot consumers). The draw
## loop calls [method flatten_for_node] which filters by archetype affinity.
func flatten_all() -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	for pack in packs:
		if pack == null:
			continue
		for pool in pack.pools:
			if pool != null:
				out.append_array(pool.to_entries())
	return out


## Per-node flatten. Selects every pool whose `archetype_stat` matches the
## node's `primary_stat` **or** is empty (`&""` = universal — armor,
## node_health, movement_points, … stay shared across all archetypes, D7).
## There is no off-archetype phase and no defensive phase — universal
## pools ARE the shared content, gated by tier tag and budget, not by pool
## role.
## The second key is `subtype` (#1056): a pool is selected iff its `subtypes`
## is empty (`[]` = any, every pool authored today) or names this node's
## subtype — see [method StatPool.admits_subtype]. `null` resolves to
## [method NodeSubtype.regular], so an unset node draws what the default draws
## and today's one-key callers are unchanged.
func flatten_for_node(
		primary_stat: StringName,
		subtype: NodeSubtype = null,
) -> Array[ModifierPoolEntry]:
	var effective := subtype if subtype != null else NodeSubtype.regular()
	var out: Array[ModifierPoolEntry] = []
	for pack in packs:
		if pack == null:
			continue
		for pool in pack.pools:
			if pool == null:
				continue
			if pool.archetype_stat != &"" and pool.archetype_stat != primary_stat:
				continue
			if not pool.admits_subtype(effective):
				continue
			out.append_array(pool.to_entries())
	return out


## Markdown-ish dump of the whole set — what the print-tool emits.
func format_tables() -> String:
	var lines: PackedStringArray = []
	lines.append("ModifierPoolSet — %d packs (v4 spend-until-broke)" % packs.size())
	for pack in packs:
		if pack == null:
			lines.append("(null pack)")
			continue
		lines.append("")
		lines.append(pack.format_table())
	return "\n".join(lines)


func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray()
