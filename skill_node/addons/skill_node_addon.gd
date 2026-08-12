@tool
class_name SkillNodeAddon
extends Node2D

## Component-as-node attached to a SkillNode as a plain direct child. Carries
## stat modifiers (entity- or node-scoped), a visual, and behavior hooks
## that other systems dispatch into (e.g. SkillBlade.apply_to_blade for
## phantom-blade modifications).
##
## [b]Attaching is just [code]skill_node.add_child(addon)[/code][/b] (#334).
## There is no anchor node to file into and no [code]attach_addon()[/code] to
## call — procgen, keystone stamping, loot, editor authoring and (eventually)
## the player all use the one path. Ordering is free: an addon parented before
## the carrier enters the tree is adopted by the carrier's `_ready` sweep.
##
## [b]Positioning contract:[/b] an addon's own transform stays identity. It
## renders concentric with the carrier, centred on the carrier's origin, and
## inherits the carrier's transform for free. An addon that wants an offset or
## rotated element bakes that into its own [i]child[/i] visuals — never into
## its root transform, which the carrier assumes is neutral.
##
## Only DIRECT children are adopted. Nesting an addon under `Visuals` or under
## another addon resolves [member carrier] (the lookup walks up) but never
## attaches — an explicit non-contract, not a half-supported arrangement.
##
## Lifecycle: on becoming a child of a SkillNode, the carrier transfers our
## modifiers into its own arrays and (if allocated) the entity board.
## Symmetric on removal. The carrier owns the "is-this-mod-attached" truth —
## addons just hand off and reclaim.
##
## [b]In the editor the modifier transfer is skipped[/b] — an addon shows its
## visuals but grants no stats, because [member SkillNode.modifiers] is an
## `@export` and writing derived modifiers there would serialize them into the
## `.tscn`. See #335.
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
## Free-text tooltip description — lets a behaviour-only addon (no modifiers,
## e.g. Clamp) still describe itself on the carrier's hover tooltip. Empty by
## default; [method SkillNode.get_addon_tooltip_sections] surfaces a section
## whenever either this or [method get_tooltip_modifiers] is non-empty.
@export_multiline var description: String = ""
## Tooltip icon for this addon's AddonItem — a game-icons.net sprite rasterized
## by `mise run icons:update` (assets/icons/addons/). Null falls back to the
## AddonItem's built-in placeholder, so an unassigned icon ships the same way
## an unassigned description does: nothing breaks, the slot just shows the
## default. Mirrors [member SpellDef.icon] — the icon lives on the addon, not
## in a lookup table.
@export var icon: Texture2D
## Behavioural effects this addon grants to the carrier's owner while the
## carrier is allocated. Collected by [method SkillNode.get_node_effects].
## Sits alongside the modifier arrays — a pure stat bundle needs no effect.
@export var effects: Array[Effect] = []
## When true, at most one of this exact script class may sit on a carrier
## (enforced by SkillNode at child_entered_tree — duplicate is rejected).
@export var unique: bool = false
## Cost against MeleeAttackPlan's blade_size budget if this addon is offered
## as a temp upgrade (#406); 0 = not offerable. Authored per addon scene —
## single source of truth for cost, no separate id->cost table anywhere.
@export var temp_upgrade_cost: int = 0

## True when this addon was placed by the temp-upgrade UI spend (#406)
## rather than loot/procgen/editor authoring; freed automatically at the
## end of its swing-scoped lifetime instead of by explicit detach. Never
## @export — only code instantiating a temp upgrade sets this, after
## instantiate() and before add_child().
var is_temporary: bool = false

var carrier: SkillNode

## Relative z that lifts an addon above the carrier's whole `Visuals` subtree
## regardless of where it lands in child order, and below the health bars'
## relative 10. Set here rather than by the carrier — draw order is the addon's
## own presentation concern.
##
## In the script rather than per-scene because there is no base addon scene to
## put it in: each concrete addon (bunker, fortification, clamp, spike_ring,
## skill_dust) is its own standalone scene carrying this script, and
## `addon_tile.gd` builds one in code. A per-scene value would have to be
## repeated in each and would be missed by the next addon anyone adds.
##
## Uniform across every addon, so it costs no batching — see
## .claude/rules/rendering-performance.md.
const BASE_Z := 1


func _ready() -> void:
	carrier = _find_carrier()
	z_index = BASE_Z


# ─── Virtual hooks (override per addon type) ───────────────────────────────

## Node-local stat modifiers this addon contributes to its carrier's
## node_board. Defaults to the authored [member local_modifiers] array; addons
## whose contribution is computed from a scalar export (e.g. SpikeRing's
## `damage` → a blade_damage modifier) override to synthesize one.
##
## SkillNode routes these on add (via [method SkillNode.add_local_modifier]) and
## reclaims them on remove BY IDENTITY — so overrides MUST return the same
## StatModifier instance across calls (build once, cache, return the cached one).
func get_local_modifiers() -> Array[StatModifier]:
	return local_modifiers


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
# and the tooltip fan's AddonsPanel renders an item per addon. Today the
# content is StatModifier-typed (reuses the tooltip's modifier formatting +
# per-stat tint — SkillDust lists its loot payload); a richer text contract can
# extend this later. Default: no contribution.

## Own global class name — comparing a carried script's global name against
## this catches the "no real subclass" case (Bunker/Fortification attach this
## base script directly onto a scene node named e.g. "BunkerAddon" rather than
## authoring a dedicated .gd), which reads as "there is no global name" for
## THIS addon's purposes even though the base class itself has one.
const _BASE_CLASS_NAME := "SkillNodeAddon"


## Heading for this addon's tooltip section. Default derives a readable name
## from the attached script's global class name (or, when there is none — a
## scene-composed addon like Bunker/Fortification that reuses this base script
## directly — the scene node's own name), stripping a trailing "Addon" and
## splitting PascalCase: "BunkerAddon" -> "Bunker", "SpikeRingAddon" ->
## "Spike Ring". Subclass overrides win (SpikeRing -> "Spikes", SkillDust ->
## "SkillDust loot").
func get_tooltip_title() -> String:
	var scr: Script = get_script()
	var raw := ""
	if scr != null:
		raw = scr.get_global_name()
	if raw.is_empty() or raw == _BASE_CLASS_NAME:
		raw = name
	return _humanize_addon_name(raw)


## Modifiers this addon contributes to the carrier's hover tooltip. Default
## returns [member local_modifiers] + [member entity_modifiers] — every stat
## bundle this addon carries, entity- or node-scoped. Subclasses that synthesize
## their contribution from a scalar export (e.g. SpikeRing's `damage`) override
## this instead of authoring it directly into the arrays.
func get_tooltip_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = local_modifiers.duplicate()
	out.append_array(entity_modifiers)
	return out


## "BunkerAddon" -> "Bunker"; "SpikeRingAddon" -> "Spike Ring". Strips a
## trailing "Addon" suffix, then inserts a space before every uppercase letter
## that immediately follows a lowercase one.
static func _humanize_addon_name(raw: String) -> String:
	var trimmed := raw
	const _SUFFIX := "Addon"
	if trimmed.ends_with(_SUFFIX):
		trimmed = trimmed.substr(0, trimmed.length() - _SUFFIX.length())
	var out := ""
	for i in trimmed.length():
		var ch := trimmed[i]
		if i > 0 and _is_upper_letter(ch) and not _is_upper_letter(trimmed[i - 1]):
			out += " "
		out += ch
	return out


static func _is_upper_letter(ch: String) -> bool:
	return ch == ch.to_upper() and ch != ch.to_lower()


# ─── Central-emblem contract (docs/domain/skillnode-emblem.md) ────────────
# Addons contribute an EmblemSpec CARVE/BLOOM candidate the same way they
# contribute tooltip content above: aggregated by SkillNode.get_emblem_contributions,
# arbitrated by EmblemResolver. SkillNode never learns what a loot relic or a
# spell icon is — it just collects specs.

## This addon's central-emblem contribution, or null (the default) to
## contribute nothing. Override to return an [EmblemSpec] (e.g.
## [SkillDustAddon] → a LOOT-priority carve).
func get_emblem() -> Variant:
	return null


# Future hooks (add only when a concrete addon demands them):
#   on_damage_taken(amount, source) -> void
#   on_incoming_blade_contact(blade, edge_or_particle_idx) -> void
#   on_turn_start() -> void


func _find_carrier() -> SkillNode:
	var n: Node = get_parent()
	while n != null and not (n is SkillNode):
		n = n.get_parent()
	return n as SkillNode
