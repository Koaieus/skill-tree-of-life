@tool
@abstract
class_name Keystone
extends Resource

## Special-effect content carried by a [SkillNode]. Mirrors [CoreClass] but for
## node-bound effects: allocating a keystone-bearing node grants the entity
## the keystone's bonuses; deallocating removes them. Two broad shapes:
##
## - **StatKeystone** (the common 80%): a hand-crafted bundle of
##   [StatModifier]s. Apply duplicates them onto the entity's stat board.
## - **BehaviorKeystone** (overridable): subclasses override `apply`,
##   `on_turn_started`, `on_allocated`, `on_deallocated` for effects that
##   don't reduce to pure stat modifiers (signal wiring, scene-graph
##   additions, AI policy changes).
##
## The procgen-side placement is [KeystonePlacement] (step 10). Runtime
## wiring into [AllocationSystem] (allocate → keystone.apply, deallocate →
## keystone.remove) is a follow-up; the resource shape is stable.

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Stat boons granted by the keystone. Concrete subclasses may use these
## directly (StatKeystone) or ignore them entirely (BehaviorKeystone).
@export var modifiers: Array[StatModifier] = []


## Default install: duplicate-and-add each modifier to the entity's stat
## board. Returns the array of duplicated modifiers so the caller (typically
## [AllocationSystem] in the future) can keep a handle for later removal.
## Concrete subclasses may override.
func apply(entity: Entity, _node: SkillNode) -> Array[StatModifier]:
	var installed: Array[StatModifier] = []
	if entity == null or entity.stat_board == null:
		return installed
	for m in modifiers:
		if m == null:
			continue
		var dup: StatModifier = m.duplicate(true)
		entity.stat_board.add_modifier(dup)
		installed.append(dup)
	return installed


## Remove a previously-applied set of modifiers. Default removes by reference;
## subclasses may override to unwire signals / detach scene children.
func remove(entity: Entity, _node: SkillNode, installed: Array[StatModifier]) -> void:
	if entity == null or entity.stat_board == null:
		return
	for m in installed:
		if m != null:
			entity.stat_board.remove_modifier(m)


## Per-turn hook called when the owning entity's turn starts. Default no-op.
func on_turn_started(_entity: Entity, _node: SkillNode) -> void:
	pass
