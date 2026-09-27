class_name EntityState
extends RefCounted

## The authoritative, SILENT state of one [Entity] — storage only, no signals,
## no scene. An [Entity] composes one and forwards its fields into it (the
## entity's setters emit and dispatch; a write here never does), and an
## [EntityCombat] holds one: the entity's own when live, a [method clone] when
## shadow. The node twin is [NodeState].
##
## [b]Not state:[/b] the owned set (derived from the navigator mirror —
## [member EntityCombat._mirror]) and statuses ([StatusHost] stays on the slice
## whose def hooks it addresses). See #1130 and docs/domain/entity-combat.md.

## The entity's [EntityStatBoard]. Duplicated at assignment by
## [member Entity.stat_board]'s setter, never here.
var stat_board: EntityStatBoard = null
## Refcounted status markers — see docs/design/status-tags.md.
var tags: Dictionary[StringName, int] = {}
## The real [SkillNode] the core sits on — IDENTITY, shared by a clone.
var core_location: SkillNode = null
## Live [Effect] attachments, in grant order — [member Entity._effect_instances].
var effect_instances: Array[EffectInstance] = []


## A detached copy at COMBAT depth: [member stat_board] via
## [method StatBoard.clone_live], [member tags] duplicated, [member core_location]
## by identity. [member effect_instances] is left EMPTY: an effect twin binds
## its context to the slice that holds it ([method EffectInstance.clone_for]),
## so twinning the ledger is [method EntityCombat.snapshot]'s job, not state's.
func clone() -> EntityState:
	var c := EntityState.new()
	c.stat_board = stat_board.clone_live() as EntityStatBoard if stat_board != null else null
	c.tags = tags.duplicate()
	c.core_location = core_location
	return c
