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

## The fraction of every node's draw weight that goes to universal
## (`archetype_stat == &""`) content, whatever the node's archetype (#975).
## [method flatten_for_node] rescales the universal entries to hit it, so a
## universal pool's `pool_weight` means "share *within* universal" and
## authoring a pool on either side never shifts the other side's share.
## Exact before the draw's affordability filter, approximate after it.
## Tuning: one number. `>= 1` diverges and is clamped (and flagged).
@export_range(0.0, 1.0) var universal_share: float = 0.2

## Largest share the slice formula accepts; `share / (1 - share)` diverges at 1.
const _MAX_SHARE := 0.999

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
## The selected universal entries are then rescaled to [member universal_share]
## of the total weight (#975) — see [method _apply_universal_slice].
func flatten_for_node(
		primary_stat: StringName,
		subtype: NodeSubtype = null,
) -> Array[ModifierPoolEntry]:
	var effective := subtype if subtype != null else NodeSubtype.regular()
	var out: Array[ModifierPoolEntry] = []
	var universal: Array[ModifierPoolEntry] = []
	var a_mass := 0.0
	var u_mass := 0.0
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
			var entries := pool.to_entries()
			for e in entries:
				if pool.archetype_stat == &"":
					universal.append(e)
					u_mass += e.weight
				else:
					a_mass += e.weight
			out.append_array(entries)
	_apply_universal_slice(out, universal, a_mass, u_mass)
	return out


## Scales `universal` (entries also held by `out`) so they carry exactly
## [member universal_share] of the total weight. Entries are minted fresh by
## [method StatPool.to_entries] on every flatten, so this mutates nothing
## authored. No-op without universal content or without archetype content
## (scaling to a zero target would delete a pack-less node's only content);
## `share <= 0` drops the universal entries from `out` instead.
func _apply_universal_slice(out: Array[ModifierPoolEntry],
		universal: Array[ModifierPoolEntry], a_mass: float, u_mass: float) -> void:
	if u_mass <= 0.0 or a_mass <= 0.0:
		return
	if universal_share <= 0.0:
		for e in universal:
			out.erase(e)
		return
	var share := minf(universal_share, _MAX_SHARE)
	var scale := (a_mass * share / (1.0 - share)) / u_mass
	for e in universal:
		e.weight *= scale


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
	var out := PackedStringArray()
	if universal_share >= 1.0:
		out.append("universal_share >= 1 leaves no room for archetype content; clamped to %.3f." % _MAX_SHARE)
	return out
