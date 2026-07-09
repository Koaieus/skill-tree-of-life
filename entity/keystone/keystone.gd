@tool
@abstract
class_name Keystone
extends Resource

## Special-effect content carried by a [SkillNode]. Mirrors [CoreClass] but for
## node-bound content: allocating a keystone-bearing node grants the entity the
## keystone's bonuses; deallocating removes them.
##
## Two broad shapes, both expressed through [Effect]:
##
## - **StatKeystone** (the common 80%): a hand-crafted bundle of [StatModifier]s
##   in [member modifiers]. Wrapped implicitly into a [StatEffect].
## - **Behavioural**: author [Effect] subclasses into [member effects] — auras,
##   per-turn rules, anything with a hook.
##
## Runtime wiring lives in [AllocationSystem] (`allocate` → `entity.grant_effect`,
## `deallocate` → revoke), keyed by the source node, and the grant ledger on each
## [EffectInstance] is what makes revocation exact. Procgen-side placement is
## [KeystonePlacement].

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
## Stat boons granted while the carrier node is allocated. Surfaced to the
## entity as an implicit [StatEffect] — see [method get_effects].
@export var modifiers: Array[StatModifier] = []
## Behavioural effects granted alongside [member modifiers]. Shared resources:
## keep runtime state on the [EffectInstance], never on the effect.
@export var effects: Array[Effect] = []

## Lazily-built wrapper exposing [member modifiers] as an [Effect]. Stateless,
## so caching it on this shared resource is safe — the per-entity ledger lives
## on the [EffectInstance] that each grant creates.
var _modifier_effect: StatEffect = null


## Everything this keystone grants, as effects. [AllocationSystem] grants each
## against the carrier node, so deallocating the node revokes exactly these.
func get_effects() -> Array[Effect]:
	var out: Array[Effect] = effects.duplicate()
	if modifiers.is_empty():
		return out
	if _modifier_effect == null:
		_modifier_effect = StatEffect.new()
		_modifier_effect.display_name = display_name
		_modifier_effect.description = description
		_modifier_effect.icon = icon
		_modifier_effect.modifiers = modifiers
	out.append(_modifier_effect)
	return out
