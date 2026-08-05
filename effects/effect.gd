@tool
@abstract
class_name Effect
extends Resource

## Persistent, hook-driven behaviour carried by a [CoreClass], a [Keystone], or
## a [SkillNodeAddon], and dispatched by the [Entity] that owns it.
##
## [b]Not to be confused with [OnHitEffect][/b], which is transient: it fires
## once as a spell lands on a node and keeps no state. An [Effect] is granted,
## lives, reacts to gameplay moments, and is revoked. Sibling concepts, not a
## hierarchy.
##
## [b]Composition, not a subclass zoo.[/b] There is no `TurnStartEffect` /
## `BattleStartEffect` split — those would be uncomposable (an effect can't be
## both). Triggers are [i]methods[/i]; the composite is an `Array[Effect]` on
## the carrier, which the Godot inspector edits natively. So no `CompositeEffect`
## is needed either.
##
## [b]Hooks are declared, not inherited.[/b] This base defines none of the `_on_*`
## world/combat hooks, so `has_method()` is an exact test of "does this effect
## care" — and [Entity] buckets by hook once at grant time, making dispatch
## O(interested) rather than O(all effects). Implement only what you need:
## [codeblock]
## func _on_core_moved(ctx: EffectContext, from: SkillNode, to: SkillNode) -> void:
##     ...
## [/codeblock]
##
## The two lifecycle hooks below are the exception — defined here and always
## called. Everything else is optional and listed in [constant HOOKS].
##
## [b]Effects are shared resources.[/b] One `.tres` may sit on many entities.
## Never store runtime state on the effect; use the [EffectInstance] ledger via
## [EffectContext].

## Every legal optional hook name. A GUT test asserts each `_on_*` method on
## each subclass appears here — the price of the `has_method` approach is that
## a typo would otherwise silently never fire.
const HOOKS: Array[StringName] = [
	&"_on_turn_start",
	&"_on_turn_end",
	&"_on_node_allocated",
	&"_on_node_deallocated",
	&"_on_core_moved",
	&"_on_level_up",
	&"_on_entity_dying",
	&"_on_attack_launched",
	&"_on_node_damaged",
	&"_on_killing_blow",
]

## Hooks defined on this base and dispatched unconditionally, never bucketed.
const LIFECYCLE_HOOKS: Array[StringName] = [&"_on_granted", &"_on_revoked"]

@export var display_name: String = ""
## Prose shown in tooltips. Leave blank to auto-derive from [member modifiers]
## via [method get_description].
@export_multiline var description: String = ""
## Optional iconography. Consumers fall back to a letter glyph when null, as
## [SpellPickerButton] does.
@export var icon: Texture2D = null
## Stat boons granted for as long as the effect is attached. Applied by the
## default [method _on_granted].
@export var modifiers: Array[StatModifier] = []


## Composition-mutation seam for SkillNode's local-scale mutator (#376,
## decision 8). Default returns `null` = no composition scaling. An override
## returns an Array[StatModifier] — the scaled leaf-set that replaces this
## effect's granted contribution on the entity board — or
## [constant StatModifier.UNSCALED]. Effects must NOT return a Float: their
## canonical [member modifiers] are shared .tres instances, so the mutator
## never value-scales them (a Float override is rejected with a push_warning).
func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return null


## Called once when the effect attaches to an entity. Default grants
## [member modifiers] to the entity's board.
##
## This is also where an effect does its initial world read — an [AuraEffect]
## computes its first buffed set here, because the initial core placement
## (spawn, or scene-export deserialization) never passes through `move_core`
## and so would never fire `_on_core_moved`.
func _on_granted(ctx: EffectContext) -> void:
	for m in modifiers:
		if m != null:
			ctx.grant(m)


## Called once when the effect detaches. Default revokes everything the effect
## granted, wherever it landed.
func _on_revoked(ctx: EffectContext) -> void:
	ctx.revoke_all()


## One-line summary for tooltips. Falls back to folding the modifier set into
## words, mirroring how [PropagationConfig.get_description] composes its parts.
func get_description() -> String:
	if not description.is_empty():
		return description
	return describe_modifiers(modifiers)


## "+10 Strength, +20% increased Armor" — thin join over [method
## StatModifier.format] (#305), the single shared modifier-to-sentence home.
static func describe_modifiers(mods: Array[StatModifier]) -> String:
	var parts: PackedStringArray = []
	for m in mods:
		if m == null:
			continue
		parts.append(m.format())
	return ", ".join(parts)


## The optional hooks this effect actually implements. Read once per grant.
func implemented_hooks() -> Array[StringName]:
	var out: Array[StringName] = []
	for h in HOOKS:
		if has_method(h):
			out.append(h)
	return out
