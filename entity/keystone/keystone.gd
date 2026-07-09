@tool
class_name Keystone
extends Resource

## Named, landmark content authored onto a [SkillNode] — a [b]blueprint[/b], not
## a behaviour. It carries identity (name, prose, icon) and a payload of
## [Effect]s; allocating the carrier node grants the payload to the owner,
## deallocating revokes it.
##
## [b]The payload is plain [Effect]s.[/b] A hand-crafted stat bundle is one
## [StatEffect] in [member effects]; anything behavioural (auras, per-turn
## rules) is an [Effect] subclass alongside it. Keystone deliberately carries no
## `modifiers` array of its own — it was field-for-field [Effect]'s, and the
## duplication meant two homes for the same content (#149).
##
## Runtime wiring lives in [AllocationSystem] (`allocate` → `entity.grant_effect`,
## `deallocate` → revoke), keyed by the source node, and the grant ledger on each
## [EffectInstance] is what makes revocation exact. Procgen-side placement is
## [KeystonePlacement].
##
## [b]Shared resource.[/b] One `.tres` may sit on many nodes and many entities.
## Keep runtime state on the [EffectInstance], never here.

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
## Everything this keystone grants while its carrier node is allocated.
## [AllocationSystem] grants each against the carrier, so deallocating the node
## revokes exactly these.
@export var effects: Array[Effect] = []
