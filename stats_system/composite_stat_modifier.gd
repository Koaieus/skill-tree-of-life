@tool
class_name CompositeStatModifier
extends StatModifier

## A modifier pack: one atom for storage/authoring that expands into its children
## wherever modifiers are applied or listed. `loots_as_unit` makes loot treat it
## all-or-nothing. Inert by design: only `children` apply; `add_modifier` flattens.
## See docs/domain/stat-board-classes.md

## The real modifiers this bundle grants. Authored order is preserved through
## [method flatten], so a UI listing the leaves keeps that order.
@export var children: Array[StatModifier] = []

## Whether [LootSystem]'s core loot draw treats this pack as ONE all-or-nothing
## candidate (`true`, the default — preserves the pre-D-27 behaviour) or
## expands it into one candidate PER CHILD (`false`) before the draw's
## lootability filter runs. Apply-time behaviour is unaffected either way —
## [method StatBoard.add_modifier] always flattens, so this only decides what
## the loot draw counts as its unit. See [member CoreClass.modifiers] /
## `attribute_baseline.tres` for the `false` case.
@export var loots_as_unit: bool = true


## Expand to the leaf modifiers, recursively (a nested composite flattens too).
## Overrides [method StatModifier.flatten] — the seam described on the base.
## Recursive, because a bundle is one loot candidate made of the same tiny
## parts (#522). [member loots_as_unit] rides along: it decides what the loot
## draw counts as its unit, so a peer reconstructing this pack needs it.
func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_COMPOSITE
	d["loots_as_unit"] = loots_as_unit
	var kids: Array = []
	for c in children:
		if c != null:
			kids.append(c.to_dict())
	d["children"] = kids
	return d


func read_dict(d: Dictionary) -> void:
	super(d)
	loots_as_unit = bool(d.get("loots_as_unit", true))
	children = StatModifierCodec.array_from_dicts(d.get("children", []))


func flatten() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for c in children:
		if c != null:
			out.append_array(c.flatten())
	return out


## Recurse into the children — a bundle's dependency edges are its leaves'.
## Overrides [method StatModifier.collect_formula_edges] so a bundle that closes
## a cycle no single leaf closes is still caught (#322); the container itself is
## inert and contributes nothing of its own.
func collect_formula_edges(out: Dictionary) -> void:
	for c in children:
		if c != null:
			c.collect_formula_edges(out)


## Defensive summary for any display path that renders a modifier WITHOUT
## flattening first (the intended paths — tooltip, loot card — do flatten).
## Joins each leaf's own contribution so a stray render shows the bundle, not
## the inherited "+1" phantom from the vestigial `value` field.
func contribution_text(board: StatBoard = null) -> String:
	var parts: Array[String] = []
	for c in flatten():
		parts.append(c.contribution_text(board))
	return " · ".join(parts)


## Same idea as [method contribution_text] but for the full sentence: joins
## each leaf's [method StatModifier.format] output. Uses ", " (matching
## [method Effect.describe_modifiers]'s join), NOT contribution_text's " · "
## — a bundle of full sentences reads as a list, not a compact value stack.
func format() -> String:
	var parts: Array[String] = []
	for c in flatten():
		parts.append(c.format())
	return ", ".join(parts)


## Hide the inherited leaf fields — they are vestigial on a container (a
## designer authoring a composite tunes [member children], nothing else).
## Mirrors PoolStatDef hiding the BOOL `value_type`.
func _validate_property(property: Dictionary) -> void:
	if property.name in ["stat_id", "operation", "value", "formula", "priority"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR
