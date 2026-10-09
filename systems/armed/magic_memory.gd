class_name MagicMemory
extends RefCounted

## An entity's magic "last choice" (see [SeatMemory]).

## The picked spell — the next [MagicAttackPlan] is minted with it. Null means
## "the plan's bundled fallback". Write it through [method ArmedStack.select_spell],
## which re-equips an armed plan and announces the pick.
var selected_spell: SpellDef = null

## Last infusion per spell, `{spell id: {concept id: points}}`. Taken when a
## magic plan leaves a spell and put back, clamped, when a plan equips it again
## ([method ArmedStack.remember_infusion] / [method ArmedStack.restore_infusion]).
var last_infusion: Dictionary[StringName, Dictionary] = {}
