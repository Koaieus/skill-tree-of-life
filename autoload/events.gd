@tool
extends Node

signal skill_node_hovered(node: SkillNode)
signal skill_node_unhovered

## Re-emitted by SkillNode.take_damage so UI (floating damage numbers, screen
## shake, etc.) can subscribe once globally instead of binding to every node.
signal skill_node_damaged(node: SkillNode, amount: float, source: Variant)

## Emitted when a non-core node's current_hp reaches 0. BattleSystem listens
## and runs the forced-deallocation cascade (dealloc + wound + core HP loss).
signal skill_node_depleted(node: SkillNode)

## Emitted when a spell's [IncidentReducer] resolves to null at a node
## (overlap-cancel, even-cancel, custom-cancel) — the spell visibly fizzles
## there. VFX hooks listen to pop a dissipate effect; battle log can record.
## Also lives on [member AttackOutcome.cancellations] as a list for replay.
signal spell_incident_cancelled(cancellation: SpellCancellation)
