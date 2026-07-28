@tool
class_name ModSlabRow
extends Control

## One `StatModifier` rendered as its own mini "glass slab" — a single Label
## carrying the full sentence from [method StatModifier.format] (#305), on a
## background tinted by the target stat's [member StatDef.tint_color], read
## RAW (no row-local saturate/lift). The operator carries no color of its
## own — it lives entirely in the text (`+18% increased`, `bonus`, `Max `,
## ...). Content row for Tooltip V2 (epic #159, #221).
##
## Reused standalone (#306's "you gained these" toast instantiates slabs with
## nothing driving them) as well as inside [AddonItem]'s modifier list (#293).
## Must render correctly the moment [method bind] is called, with no
## assumption about whether/when [method set_progress] is ever invoked.
##
## Reveal is driven externally via [method set_progress] against the shared
## fixed-clock / progress(0..1) contract (see fan_panel.gd / docs/domain/
## tooltip-fan.md) — this row owns no Tween, matching the other #293 rows
## (PanelHeader, StatValueRow, AddonItem).

## Scale the row starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

@onready var _background: ColorRect = %Background
@onready var _label: Label = %Label


## Renders `m.format()` (the full sentence, stat name included — #305) into
## the slab's Label, and tints the slab background by the target stat's
## [member StatDef.tint_color], read raw. Falls back to [constant Color.WHITE]
## only if the def can't be resolved (not expected for a real stat_id).
##
## `m` is assumed to be a leaf modifier — a [CompositeStatModifier] has no
## single meaningful `stat_id`; callers are specified to flatten before
## binding one row per leaf (see `.claude/rules/stats-system.md` §Composite).
func bind(m: StatModifier) -> void:
	_label.text = m.format()
	var def := StatRegistry.get_def(m.stat_id)
	_background.color = def.tint_color if def != null else Color.WHITE


## Applies the fan reveal at clock position `t` (0..1): cubic ease-out driving
## scale (start_scale → 1.0) and fade (0 → 1). Matches [method FanPanel.set_progress].
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
