@tool
class_name TagAuraEffect
extends AuraEffect

## [AuraEffect] on the tag channel: radiates a status [member tag] (not a numeric
## modifier) over the same reach/metric/distance_scale knobs, granted through
## [method EffectContext.grant_tag] instead of `grant_scaled`. See
## docs/design/status-tags.md.
##
## [b]A payload, not a second aura.[/b] Everything about the walk — the three
## knobs, the origin rule (`source_node ?? core_location`), the batching, the
## #626 incremental topology paths — is inherited, so this file is exactly the
## two seams [AuraEffect] documents: [method _has_payload] and [method _grant_to].
## The previous verbatim copy of the walk is why this channel spent two issues
## missing the incremental and batched paths the numeric one already had.
##
## [member distance_scale] gates membership here rather than magnitude — a tag
## is granted/not granted, so a zero scale at a given distance excludes the
## node (mirrors how [ShellScale] carves a ring for [AuraEffect]); any nonzero
## scale grants it at full strength.
##
## Inherited batching is a cheap no-op on this channel: a tag grant touches no
## [Stat], and [method EffectContext.board_for] never materializes a board that
## doesn't exist yet, so [method AuraEffect._open_batch] only ever brackets
## boards some other effect already minted.

## The tag this aura grants. Empty means "not configured" — the aura no-ops.
@export var tag: StringName = &""


func _has_payload() -> bool:
	return tag != &""


func _grant_to(ctx: EffectContext, node: SkillNode, _scale: float) -> void:
	ctx.grant_tag(tag, node)


func get_description() -> String:
	if not description.is_empty():
		return description
	var label := String(tag)
	if reach == null:
		return "Grants %s to every node in your constellation" % label
	return "Grants %s in reach" % label
