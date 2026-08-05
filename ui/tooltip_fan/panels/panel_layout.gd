@tool
class_name PanelLayout
extends HoloPanel

## Layout skin for a tooltip fan panel (#344): the holo visual AND the layout
## root in one node. Sits as the FanPanel root's skin child (so FanPanel's
## glow forwarding and FanAnchor's rect derivation keep working unchanged),
## hugging a [PanelContent] child's minimum size + its authored padding.
##
## Before #344 each panel script copied the content's size into the skin's
## rect by hand (`_resize_to_content`), and the fixed-envelope panels authored
## the skin rect and the content rect as two independent siblings that could
## drift apart. Here size flows DOWN: the content Controls compute their own
## minimum size, this node sizes itself to it (floored at [member min_size]),
## and the content (full-rect anchored) re-centres automatically.
##
## [member min_size] is the pre-bind envelope authored in the scene — the
## footprint the static fan-overlap test measures, and the floor the panel
## keeps while it has no content. Runtime [method bind] may grow it; it never
## shrinks a crown envelope that was authored with headroom.

## Floor for the skin's rect — authored per scene as the pre-bind footprint
## (the static fan-overlap test measures exactly this rect).
@export var min_size: Vector2 = Vector2.ZERO

## When true, the skin hugs BELOW [member min_size] once the content actually
## has rows — used by panels whose envelope is only a pre-bind placeholder
## (the procgen debug readout is "content-driven and unbounded" by design).
## While the content column is empty (pre-bind) the authored envelope still
## stands, so the static overlap test and the editor preview see the authored
## footprint.
@export var hug_down: bool = false

var _content: PanelContent = null


func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is PanelContent:
			_content = child as PanelContent
			_content.layout = self
			break
	if _content != null:
		# Belt-and-braces alongside PanelContent's own notification report:
		# the content's resized signal covers any layout pass the notification
		# path missed, and is idempotent with it.
		_content.resized.connect(fit_to_content)
	fit_to_content()


## Sizes this skin to the content's minimum size plus padding, floored at
## [member min_size] (or hugging below it in [member hug_down] mode once the
## content has rows). Only ever writes `size` — the skin's authored position
## (centred offsets) is untouched, so the panel never drifts off its anchor.
func fit_to_content() -> void:
	if _content == null:
		return
	var target := _content.fit_target_size()
	if hug_down and _content.get_combined_minimum_size().y > 0.0:
		size = Vector2(maxf(min_size.x, target.x), target.y)
	else:
		size = Vector2(maxf(min_size.x, target.x), maxf(min_size.y, target.y))
