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


static func make(main: String, sub: String = "", s: Style = Style.DEFAULT) -> BannerRequest:
	var r := BannerRequest.new()
	r.main_text = main
	r.sub_text = sub
	r.style = s
	return r
