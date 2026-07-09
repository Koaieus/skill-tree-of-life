@tool
class_name SkillNodeAddon
extends Node2D

## Component-as-node attached to a SkillNode under its AddonAnchor. Carries
## stat modifiers (entity- or node-scoped), a visual, and behavior hooks
## that other systems dispatch into (e.g. SkillBlade.apply_to_blade for
## phantom-blade modifications).
##
## Lifecycle: when added as a child of a SkillNode's AddonAnchor, the
## carrier transfers our modifiers into its own arrays and (if allocated)
## the entity board. Symmetric on removal. The carrier owns the
## "is-this-mod-attached" truth — addons just hand off and reclaim.
##
## - `entity_modifiers`: appended to carrier.modifiers (the same
##   `Array[StatModifier]` AllocationSystem already iterates) on add,
##   erased on remove. While the carrier IS allocated we also push/pop
##   live on the entity stat_board so the effect is immediate.
## - `local_modifiers`: routed to carrier.node_board via [method SkillNode._ensure_local_stat]
##   on add, removed on remove. Applies regardless of allocation; an
##   unallocated node is inert in combat anyway.
##
## Future stacking cap (e.g. "1 + 1/<stat>" addon capacity) lives at
## allocation/edit time and doesn't touch this class.

@export var entity_modifiers: Array[StatModifier] = []
@export var local_modifiers: Array[StatModifier] = []
## Behavioural effects this addon grants to the carrier's owner while the
## carrier is allocated. Collected by [method SkillNode.get_node_effects].
## Sits alongside the modifier arrays — a pure stat bundle needs no effect.
@export var effects: Array[Effect] = []
## When true, at most one of this exact script class may sit on a carrier
## (enforced by SkillNode at child_entered_tree — duplicate is rejected).
@export var unique: bool = false

var carrier: SkillNode


func _ready() -> void:
	carrier = _find_carrier()


# ─── Virtual hooks (override per addon type) ───────────────────────────────

## Called by SkillNode._sync_visuals whenever the carrier's radius changes.
## Override to redraw at the new size.
func configure_visual(_radius: float) -> void:
	pass


## Called once per source SkillNode that carries this addon, by
## SkillBlade.build_from_skill_nodes AFTER BladeState.build returns.
## `particle_idx` is this carrier's index in state.positions.
## Transient — BladeState is rebuilt each simulate(), so this runs every swing.
func apply_to_blade(_state: BladeState, _particle_idx: int) -> void:
	pass


# ─── Tooltip content contract ──────────────────────────────────────────────
# Addons surface extra content on the carrier's hover tooltip by overriding the
# pair below; the carrier aggregates them via SkillNode.get_addon_tooltip_sections,
# and SkillNodeTooltip renders a titled section per non-empty addon. Today the
# content is StatModifier-typed (reuses the tooltip's modifier formatting +
# per-stat tint — SkillDust lists its loot payload); a richer text contract can
# extend this later. Default: no contribution.

## Heading for this addon's tooltip section. Only shown when
## [method get_tooltip_modifiers] is non-empty.
func get_tooltip_title() -> String:
	return ""


## Modifiers this addon contributes to the carrier's hover tooltip. Empty (the
## default) means the addon adds no tooltip section.
func get_tooltip_modifiers() -> Array[StatModifier]:
	return []


# Future hooks (add only when a concrete addon demands them):
#   on_damage_taken(amount, source) -> void
#   on_incoming_blade_contact(blade, edge_or_particle_idx) -> void
#   on_turn_start() -> void


func _find_carrier() -> SkillNode:
	var n: Node = get_parent()
	while n != null and not (n is SkillNode):
		n = n.get_parent()
	return n as SkillNode
