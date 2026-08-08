@tool
class_name CompositeStatModifier
extends StatModifier

## A modifier pack, optionally atomic for loot (D-27, #279): a container that
## bundles several [StatModifier]s into ONE atom for the storage / authoring
## layer, while transparently expanding into its children wherever modifiers
## are actually APPLIED to a board or fully LISTED in the UI (#183).
##
## Two independent uses, both by reference — author once, drop the `.tres` into
## any [member CoreClass.modifiers] array, edit the pack and every class
## composing it changes:
##
## - [b]Plain authoring reuse[/b] ([member loots_as_unit] `false`) — a shared
##   batch like `+10 STR/DEX/INT` with nothing all-or-nothing about it. The loot
##   draw offers each child as its own candidate.
## - [b]A loot bundle[/b] ([member loots_as_unit] `true`, the default) — a
##   class-identity buff/debuff pair that is only balanced as a unit, a strong
##   buff yoked to a real tax (`ninja_core`'s `mod_budget_pack`). The
##   pick-N-from-M loot draw counts it once, all-or-nothing, so a collector
##   can't cherry-pick the buff and shed the debuff.
##
## INERT BY DESIGN: it contributes no stat of its own. The inherited
## `stat_id` / `operation` / `value` / `formula` / `priority` fields are
## meaningless on a container and are hidden from the inspector (see
## [method _validate_property]) — only the [member children] bind and apply.
## Because [method StatBoard.add_modifier] flattens before routing, a child's
## `emit_changed()` reaches its target Stat through the ordinary
## `_on_dependent_modifier_changed` wiring; the container never proxies signals.
##
## `duplicate(true)` deep-copies [member children] (verified — Godot recurses
## into an exported Array of Resources), so the per-element dup discipline the
## stats rule requires for formula-bound modifiers holds for a bundle too — no
## `duplicate()` override needed.
##
## Nesting is legal ([method flatten] recurses), though nothing needs it today.

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
