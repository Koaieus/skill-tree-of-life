class_name BannerRequest
extends RefCounted

## A single banner display request — what to show on the main line, what to
## show on the sub line (optional), and what visual style to apply. Submit
## via [method BannerLayer.enqueue] or [method BannerLayer.enqueue_now].
##
## Styles are intentionally semantic, not visual ("LEVEL_UP" vs. "gold-tinted")
## so the look can evolve without touching call sites.

enum Style {
	DEFAULT,
	PHASE,
	LEVEL_UP,
	KILL,
	DEATH,
}

var main_text: String = ""
var sub_text: String = ""
var style: Style = Style.DEFAULT
## Optional staleness context. Key: `entity: Entity`. BannerLayer drops the
## request on dequeue if a different entity is now acting.
var context: Dictionary = {}


static func make(main: String, sub: String = "", s: Style = Style.DEFAULT) -> BannerRequest:
	var r := BannerRequest.new()
	r.main_text = main
	r.sub_text = sub
	r.style = s
	return r


## Same as [method make] but stamps `{entity}` into [member context] so
## BannerLayer can drop the banner if a different entity is acting by the
## time it dequeues.
static func make_for_entity(
		main: String,
		sub: String,
		s: Style,
		entity: Entity) -> BannerRequest:
	var r := make(main, sub, s)
	r.context = {&"entity": entity}
	return r


## True if `other` would display the same text + style as `self`. Used by
## BannerLayer to dedup adjacent enqueues.
func equivalent_to(other: BannerRequest) -> bool:
	if other == null:
		return false
	return main_text == other.main_text \
			and sub_text == other.sub_text \
			and style == other.style
