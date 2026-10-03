@tool
extends StatusArrow

## The owner's poison look: a neon tip at
## [constant Emissive.ALERT] fading back to the plain shaft along its length,
## and an occasional froth bubble left along the flight path.
##
## The froth is a sparse `%Froth` [GPUParticles2D] in world space, tinted like
## the trail; [member froth_density] scales its emission through
## [member GPUParticles2D.amount_ratio], so a full volley thins out together
## instead of carpeting the board. A dud or absorbed shot keeps the base look.

## Share of `%Froth`'s authored `amount` actually emitted (0 = none). Tuned for
## a 20-arrow volley to stay readable. Tentative knob.
@export_range(0.0, 1.0, 0.01) var froth_density: float = 0.35:
	set(v):
		froth_density = v
		_paint_status()


func drain_seconds() -> float:
	var froth := _froth()
	return maxf(super.drain_seconds(), froth.lifetime if froth != null else 0.0)


func _on_launch() -> void:
	super._on_launch()
	var froth := _froth()
	if froth != null and has_status() and not _emit_stopped:
		froth.emitting = true


func _stop_trail() -> void:
	super._stop_trail()
	var froth := _froth()
	if froth != null:
		froth.emitting = false


func _paint_status() -> void:
	super._paint_status()
	var tip := _tip()
	var froth := _froth()
	if tip == null or froth == null:
		return
	var c := Color(status_tint.r, status_tint.g, status_tint.b, 1.0)
	if _dud:
		tip.vertex_colors = PackedColorArray()
	else:
		var tail := Color(c.r, c.g, c.b, 0.0)
		# The vertex colours alone author the tier; a non-white color would multiply in.
		tip.color = Color.WHITE
		tip.vertex_colors = PackedColorArray([Emissive.at(c, Emissive.ALERT), tail, tail])
	froth.visible = has_status() and not _dud and not _absorbed
	froth.modulate = Emissive.at(c, Emissive.LABEL)
	froth.amount_ratio = froth_density


func _froth() -> GPUParticles2D:
	return get_node_or_null(^"%Froth") as GPUParticles2D
