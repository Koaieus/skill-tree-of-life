class_name StatusDef
extends Resource

## The shared definition of a node status — poison, blindness, armor break
## (#868 hub, #872 plumbing). Authored once as a `.tres`, referenced by every
## node carrying that status; it holds NO runtime state. The per-node state
## (current power) lives on [NodeCombat]'s status slice as a [NodeStatus] row.
##
## A status is a bounded, decaying power: [method NodeCombat.apply_status] adds
## or refreshes it (per [member reapply]), [method NodeCombat.tick_statuses]
## fires [method _on_tick] and then decays it per its [member decay] slot.
## Behaviour hooks are overridable on a subclass script; the base does nothing on any of them.
##
## Display identity ([member display_name] / [member icon] / [member tint]) is
## part of the plumbing on purpose (owner, 2026-09-14): [member tint] is THE
## canonical colour of this status everywhere it is mentioned — tooltip row,
## readout, node tint, floaters — so a consumer never picks one of its own.

## Reapplication policy when the status is already on the node.
enum Reapply {
	## Keep the larger of the current and the incoming power — a re-cast
	## resets the timer, it never stacks and never shortens.
	REFRESH,
	## Add the incoming power to the current one, clamped at [member power_max].
	ACCUMULATE,
}

## What happens to the status when its node is deallocated (#879 wires it).
## Single value today; `LINGER` is the reserved door (owner, 2026-09-14),
## deliberately not built — nothing owns or ticks an unallocated node.
enum OnDealloc {
	CLEAR,
}

## Unique key — the status slice is a dictionary on this.
@export var id: StringName = &""
@export var display_name: String = ""
## Prose for tooltips. Blank → [method get_description] derives one.
@export_multiline var description: String = ""
## Optional iconography. Consumers fall back to a letter glyph when null, as
## [SpellPickerButton] does.
@export var icon: Texture2D = null
## The canonical colour of this status wherever UI mentions it (poison = green).
@export var tint: Color = Color.WHITE
## Classification tags a consumer may filter on (`&"debuff"`, `&"dot"`, …).
## Metadata only — NOT granted to the node as [method NodeCombat.add_tag] tags.
@export var tags: Array[StringName] = []
## The defender-side resistance stat (e.g. `&"poison_resistance"`): a
## fraction read on the HOST at effect time, filtering how many stacks each
## apply and tick counts, round half-down, while the row decays raw; at
## `>= 1` stacks do not land ([method StatusHost.effective_power], ADR 0031).
## Blank → unresisted.
@export var resistance_stat_id: StringName = &""
## The attacker-side stacks stat this status folds its per-hit power through
## ([method stacks_per_hit]): `<family>_stacks_per_hit` for a DoT, whose
## `dot_stacks_per_hit` parent folds in the same read, or blindness's own
## parentless stat. Blank → the authored power lands as-is.
@export var stacks_stat_id: StringName = &""
## Power is clamped to this on apply and on accumulate. `<= 0` → uncapped
## (#962): [method NodeCombat.apply_status] skips the clamp entirely.
@export var power_max: float = 1.0
## How power falls on every [method NodeCombat.tick_statuses], after
## [method _on_tick] has fired — a [FlatDecay], a [FractionDecay], or any
## sibling [StatusDecay] (#1258). Shared and stateless like this def. Defaults
## to a flat `1` per tick; `null` means the status never decays.
@export var decay: StatusDecay = FlatDecay.new()
## How stacks move between hosts — a [StatusSpread] signature, shared and
## stateless like this def. `null` → the status never spreads.
@export var spread: StatusSpread = null
## Display anchor for [method NodeStatus.normalised] (bar fill, node tint):
## `0` → use [member power_max]. An uncapped def authors one so the 0..1 scale
## survives (poison: 10).
@export var display_max: float = 0.0
@export var reapply: Reapply = Reapply.REFRESH
@export var on_dealloc: OnDealloc = OnDealloc.CLEAR


func get_description() -> String:
	if not description.is_empty():
		return description
	var name := display_name if not display_name.is_empty() else String(id)
	if decay == null:
		return "%s (max %s)" % [name, NumFmt.num(power_max)]
	return "%s (max %s, %s)" % [name, NumFmt.num(power_max), decay.describe()]


## The stacks one hit of [param authored] power lands from an attacker with
## [param board] (the defender's resistance filters later, on the host):
## ONE read of
## [member stacks_stat_id] with [param authored] as a `base_add` overlay, so
## the stat's flats add to it and its INCREASE / MORE scale it (ADR 0029).
## Rounded HALF-UP, once, here — the row is a whole count (ADR 0032) and a tie
## goes to the attacker; the `*_stacks_per_hit` stats stay FLOAT so their read
## never truncates first. A null board, a blank id or an unknown stat answers
## [param authored], rounded the same way. The landing and the on-hit readout
## both call this, so they cannot disagree.
func stacks_per_hit(board: StatBoard, authored: float) -> float:
	if board == null or stacks_stat_id.is_empty():
		return round_half_up(authored)
	var stat: Stat = board.get_stat(stacks_stat_id)
	if stat == null:
		return round_half_up(authored)
	var bins := ModifierBins.new()
	bins.base_add = authored
	var overlays: Array[ModifierBins] = [bins]
	return round_half_up(float(stat.get_value_with(overlays)))


## [param v] to the nearest whole, a half going UP. Float noise is snapped
## first: a value within `is_equal_approx` of a whole or of a half counts as
## it, so a true 2.5 computed as `2.4999…` still lands 3.
static func round_half_up(v: float) -> float:
	if is_equal_approx(v, roundf(v)):
		return roundf(v)
	var half := floorf(v) + 0.5
	if is_equal_approx(v, half):
		return floorf(v) + 1.0
	return floorf(v + 0.5)


## The power this status would carry after one tick's decay, per its
## [member decay] slot; [method NodeCombat.tick_statuses] and
## [method projected_damage] both read it. `0` means "removed". A null slot
## answers [param power] unchanged.
func decayed(power: float) -> float:
	return power if decay == null else decay.decayed(power)


## Total damage this status still has in it on [param host] at [param power],
## summed over its remaining ticks under its own decay (#962, drawn by #953's
## projected-damage overlay). The base deals none, so `0`.
func projected_damage(_host, _power: float) -> float:
	return 0.0


## The damage the NEXT tick lands on [param host] from a row of [param power]
## raw stacks — the first term of [method projected_damage], resisted and
## floored exactly as it lands. The base deals none, so `0`.
func next_tick_damage(_host, _power: float) -> float:
	return 0.0


# ── Behaviour hooks — override on a subclass; the base does nothing ─────────
#
# `host` is the composing slice a [StatusHost] serves — a [NodeCombat] today,
# an [EntityCombat] once C1 of #994 lands — duck-typed to the contract listed
# on [StatusHost]: `board()`, `get_local_value`, `get_max_hp`, `heal_damage`,
# `add_local_modifier` / `remove_local_modifier`, `host`. Untyped on purpose;
# an override keeps it untyped too.

## The status was just applied (or re-applied, or cured) on [param host];
## [param power] is the resulting post-clamp power AS RESISTED by the host
## ([method StatusHost.effective_power]) — the row keeps the raw count.
func _on_applied(_host, _power: float) -> void:
	pass


## One turn tick on [param host], BEFORE decay lands: [param before] is the
## current power, [param after] what it will be once this hook returns —
## both AS RESISTED by the host ([method StatusHost.effective_power]); the
## raw row decays after this returns. Damage
## and other effects go here (poison: [method DotTick.mint]). The host may
## vanish under you (a kill cascades into `clear_statuses`); the slice tolerates
## it, so don't assume the status still exists when you return.
func _on_tick(_host, _before: float, _after: float) -> void:
	pass


## The status left [param host] — decayed out, cured, cleared or removed.
## Fires exactly once per removal.
func _on_removed(_host) -> void:
	pass
