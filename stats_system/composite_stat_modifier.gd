@tool
class_name CompositeStatModifier
extends StatModifier

## A container that bundles several [StatModifier]s into ONE atom for the
## storage / authoring / loot layer, while transparently expanding into its
## children wherever modifiers are actually APPLIED to a board or fully LISTED
## in the UI (#183).
##
## The motivating case: a class-identity buff/debuff pair that is only balanced
## as a unit — a strong buff yoked to a real tax. Authored as a single
## [member CoreClass.modifiers] entry, it loots as a unit (the pick-N-from-M
## draw counts it once, all-or-nothing) so a collector can't cherry-pick the
## buff and shed the debuff. Generalises to arbitrary "stat modifier packs".
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


## Expand to the leaf modifiers, recursively (a nested composite flattens too).
## Overrides [method StatModifier.flatten] — the seam described on the base.
func flatten() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for c in children:
		if c != null:
			out.append_array(c.flatten())
	return out


## Defensive summary for any display path that renders a modifier WITHOUT
## flattening first (the intended paths — tooltip, loot card — do flatten).
## Joins each leaf's own contribution so a stray render shows the bundle, not
## the inherited "+1" phantom from the vestigial `value` field.
func contribution_text() -> String:
	var parts: Array[String] = []
	for c in flatten():
		parts.append(c.contribution_text())
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
