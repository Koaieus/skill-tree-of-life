@tool
class_name StatusRow
extends SlabRow

## Edge length of the status badge that prefixes the text.
@export_range(12, 64) var badge_px: int = 14:
	set(value):
		badge_px = value
		_apply_badge_px()

## Gap between the badge and the text.
const _BADGE_GAP := 4.0

@onready var _status_badge: IdentityBadge = %StatusBadge


func _ready() -> void:
	super()
	_apply_badge_px()


## The badge is the label's sibling in the inherited margin, so the label is
## pushed right by a left content margin of exactly the badge's width + gap.
func _apply_badge_px() -> void:
	if _status_badge == null or _label == null:
		return
	_status_badge.size_px = badge_px
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = badge_px + _BADGE_GAP
	_label.add_theme_stylebox_override(&"normal", pad)

## One [NodeStatus] rendered as its own mini slab — display name, the
## floored whole stacks, and (for a damage-dealing def) what the next tick
## will actually land — prefixed by the status [IdentityBadge] and tinted by
## the status def's own [member StatusDef.tint].
## Tooltip-fan Effects panel row for #876 (child of #868); the node's own
## visual tint from the same [member StatusDef.tint] is a separate consumer
## (#880), out of scope here.
##
## [b]Everything visual lives on [SlabRow][/b] (#588) — this is an inherited
## scene of `slab_row.tscn`, same shape as [ModSlabRow]: resolve the
## (text, tint) pair from the domain object, the base renders it.

## Renders "<display_name> <⌊power⌋> — <dmg> dmg next tick" for a status that
## deals damage — e.g. "Poison 12 — 9 dmg next tick" for a 12.7 row at 25%
## resistance — and bare "<display_name> <⌊power⌋>" for one that doesn't
## (curse, wither, blindness, armor-break). [param host] answers
## [method StatusDef.next_tick_damage], the SAME call the health bar's
## projection reads its first term from (#1190), so the row and the bar never
## disagree; a def that deals no damage answers `0` there and the dmg clause
## is dropped. Tinted by the def's own [member StatusDef.tint]. Falls back to
## the status id when [member StatusDef.display_name] is blank.
##
## A row the local eyes may not count ([StatusReadout.shown_power] `-1`)
## renders the bare name — no count and no dmg clause, which would leak it.
## The eyes are read off the host node's [member SkillNode.status_viewers],
## the array the node tint reads too, not a HUD bind: a bind would be a second
## copy of the same fact, free to disagree with the tint.
func bind(status: NodeStatus, host) -> void:
	var def := status.def
	var label := def.display_name if not def.display_name.is_empty() else String(def.id)
	_status_badge.identity = def.identity
	if StatusReadout.shown_power(status, _viewers_of(host)) < 0:
		bind_text(label, def.tint)
		return
	var whole := NumFmt.num(floorf(status.power))
	var dmg := def.next_tick_damage(host, status.power)
	if dmg > 0.0:
		bind_text("%s %s — %s dmg next tick" % [label, whole, NumFmt.num(dmg)], def.tint)
	else:
		bind_text("%s %s" % [label, whole], def.tint)


static func _viewers_of(host) -> Array[Entity]:
	if host is NodeCombat and (host as NodeCombat).host != null:
		return (host as NodeCombat).host.status_viewers
	return [] as Array[Entity]
