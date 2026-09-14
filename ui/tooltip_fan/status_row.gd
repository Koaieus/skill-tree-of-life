@tool
class_name StatusRow
extends SlabRow

## One [NodeStatus] rendered as its own mini slab — display name plus
## normalised power (`power / power_max`), tinted by the status def's own
## [member StatusDef.tint]. Tooltip-fan Effects panel row for #876 (child of
## #868); the node's own visual tint from the same [member StatusDef.tint] is
## a separate consumer (#880), out of scope here.
##
## [b]Everything visual lives on [SlabRow][/b] (#588) — this is an inherited
## scene of `slab_row.tscn`, same shape as [ModSlabRow]: resolve the
## (text, tint) pair from the domain object, the base renders it.

## Renders "<display_name>: <normalised power, 2dp>" — e.g. "Blindness: 0.50"
## for a status sitting at half its [member StatusDef.power_max] — tinted by
## the def's own [member StatusDef.tint]. Falls back to the status id when
## [member StatusDef.display_name] is blank.
func bind(status: NodeStatus) -> void:
	var def := status.def
	var label := def.display_name if not def.display_name.is_empty() else String(def.id)
	bind_text("%s: %.2f" % [label, status.normalised()], def.tint)
