@tool
class_name PanelContent
extends VBoxContainer

## Content column for a tooltip fan panel (#344): the Controls that drive the
## skin's size. Sits inside the panel's [PanelLayout] skin, full-rect, and
## reports layout-affecting changes up so the skin hugs whatever content
## [method bind] rendered.
##
## Before #344 the skin copied size/position from a sibling Control by hand in
## each panel script; here the flow is the other way — the content Controls
## compute their own minimum size, and the parent skin simply sizes itself to
## that minimum plus padding. That is what makes "changing the content of a
## panel resizes the holo visual with zero code changes" a structural fact
## rather than a per-panel chore.

## Inset between the content column and the skin's border, in pixels. The
## [PanelLayout] skin sizes itself to [method get_combined_minimum_size] plus
## twice this, so the padding lives in ONE authored place (here) instead of
## being duplicated between skin rect and content rect.
@export var padding: Vector2 = Vector2(8, 6)

## Set by the owning [PanelLayout] when it adopts this column.
var layout: PanelLayout = null


func _notification(what: int) -> void:
	# Two layout-affecting events, one report: the container re-sorted its own
	# children (rows added/removed/relaid) or it was resized. Which one fires
	# depends on whether the change happened to a direct child (sort) or
	# reached this container through a nested rows container growing past its
	# allocation (resize) — so report on both.
	if what == NOTIFICATION_SORT_CHILDREN or what == NOTIFICATION_RESIZED:
		if layout != null:
			layout.fit_to_content()


func fit_target_size() -> Vector2:
	return get_combined_minimum_size() + padding * 2.0
