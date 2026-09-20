class_name StatusDef
extends Resource

## The shared definition of a node status — poison, blindness, armor break
## (#868 hub, #872 plumbing). Authored once as a `.tres`, referenced by every
## node carrying that status; it holds NO runtime state. The per-node state
## (current power) lives on [NodeCombat]'s status slice as a [NodeStatus] row.
##
## A status is a bounded, decaying power: [method NodeCombat.apply_status] adds
## or refreshes it (per [member reapply]), [method NodeCombat.tick_statuses]
## fires [method _on_tick] and then decays it by [member decay_per_tick], and
## a heal cures it at [member cure_per_hp] power per hp (#875). Behaviour hooks
## are overridable on a subclass script; the base does nothing on any of them.
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

## How [member decay_per_tick] is read by [method NodeCombat.tick_statuses]
## (#962, hub #952): per def, so poison halves while blindness / armor-break
## keep their flat fade.
enum DecayMode {
	## `decay_per_tick` is flat power removed per tick; removed at `<= 0`.
	FLAT,
	## `decay_per_tick` is the FRACTION removed per tick (`0.5` = halve);
	## the tail is cleared on the tick whose post-decay value is below 1.
	FRACTION,
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
## Power is clamped to this on apply and on accumulate. `<= 0` → uncapped
## (#962): [method NodeCombat.apply_status] skips the clamp entirely.
@export var power_max: float = 1.0
## Power removed by every [method NodeCombat.tick_statuses], after
## [method _on_tick] has fired — flat power or a fraction, per
## [member decay_mode].
@export var decay_per_tick: float = 1.0
@export var decay_mode: DecayMode = DecayMode.FLAT
## Display anchor for [method NodeStatus.normalised] (bar fill, node tint):
## `0` → use [member power_max]. An uncapped def authors one so the 0..1 scale
## survives (poison: 10).
@export var display_max: float = 0.0
@export var reapply: Reapply = Reapply.REFRESH
## Power removed per hp healed on the node (#875): `0.25` means an 8-hp heal
## dents a power-5 status by 2. `0.0` → heals never cure this status.
@export var cure_per_hp: float = 0.0
@export var on_dealloc: OnDealloc = OnDealloc.CLEAR


func get_description() -> String:
	if not description.is_empty():
		return description
	var name := display_name if not display_name.is_empty() else String(id)
	if decay_mode == DecayMode.FRACTION:
		return "%s (-%d%% per turn)" % [name, roundi(decay_per_tick * 100.0)]
	return "%s (max %s, -%s per turn)" % [name, _fmt(power_max), _fmt(decay_per_tick)]


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, floor(v)) else "%.2f" % v


## The power this status would carry after one tick's decay — the one place
## the [member decay_mode] arithmetic lives; [method NodeCombat.tick_statuses]
## and [method projected_damage] both read it. `0` means "removed": a FLAT
## def floors there, a FRACTION def's tail is cut on the tick whose post-decay
## value is below 1.
func decayed(power: float) -> float:
	match decay_mode:
		DecayMode.FRACTION:
			var after := power * (1.0 - decay_per_tick)
			return after if after >= 1.0 else 0.0
		_:
			return maxf(power - decay_per_tick, 0.0)


## Total damage this status still has in it on [param node] at [param power],
## summed over its remaining ticks under its own decay (#962, drawn by #953's
## projected-damage overlay). The base deals none, so `0`.
func projected_damage(_node: NodeCombat, _power: float) -> float:
	return 0.0


# ── Behaviour hooks — override on a subclass; the base does nothing ─────────

## The status was just applied (or re-applied) to [param node];
## [param power] is the resulting post-clamp power.
func _on_applied(_node: NodeCombat, _power: float) -> void:
	pass


## One turn tick on [param node], BEFORE decay lands: [param before] is the
## current power, [param after] what it will be once this hook returns. Damage
## and other effects go here (poison: `node.take_damage(...)`). The node may
## vanish under you (a kill cascades into `clear_statuses`); the slice tolerates
## it, so don't assume the status still exists when you return.
func _on_tick(_node: NodeCombat, _before: float, _after: float) -> void:
	pass


## The status left [param node] — decayed out, cured, cleared or removed.
## Fires exactly once per removal.
func _on_removed(_node: NodeCombat) -> void:
	pass
